-- ============================================================================
-- PappaRegister - Discord account linking command for ET: Legacy
--
-- Usage (in console):
--   /register <token>
--
-- Also works in chat:
--   !register <token>
--
-- The token is shown to the user on the stats website after logging in with
-- Discord. This module posts the player's ET GUID + token to the backend
-- registration endpoint, which links the ET player to the Discord account.
--
-- Backend endpoint: POST /api/players/register
--   Body: { "etGuid": "<32 hex chars>", "token": "<registration token>" }
--   Auth: "Authorization: Bearer <token>" header (same token as ingest).
-- ============================================================================

local modname = "PappaRegister"
local version = "1.0-dev"

-- Backend endpoint
local REGISTER_API_URL = "https://et.aukko.net/api/players/register"

-- Read the backend token from a separate file at startup.
local AUTH_TOKEN = ""
local reminderQueue, reminderRequests, connections = {}, {}, {}
local reminderPollAt = 0
local STATUS_API_URL = "https://et.aukko.net/api/players/registration-status"

local json_ok, json = pcall(require, "dkjson")
if not json_ok then
    json = nil
end

local trap_GetUserinfo = et.trap_GetUserinfo
local Info_ValueForKey = et.Info_ValueForKey
local trap_Cvar_Get = et.trap_Cvar_Get

local function log(message)
    et.G_Print(string.format("^2[%s]^7 %s\n", modname, tostring(message)))
end

local function trim(s)
    s = tostring(s or "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function starts_with(s, prefix)
    s = tostring(s or "")
    prefix = tostring(prefix or "")
    return s:sub(1, #prefix) == prefix
end

local function load_api_key()
    local token = trim(os.getenv("STATS_API_TOKEN"))
    if token == "" then return nil, "STATS_API_TOKEN is not configured." end
    if token:find("[%c]") then
        return nil, "STATS_API_TOKEN contains control characters."
    end
    return token
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function say_player(clientNum, message)
    local msg = tostring(message or "")
    if msg == "" then
        return
    end

    -- Escape double quotes for server command.
    msg = msg:gsub('\\', '\\\\'):gsub('"', '\\"')
    et.trap_SendServerCommand(clientNum, string.format('chat "%s"', msg))
end

local function guid_for_client(clientNum)
    local userinfo = trap_GetUserinfo(clientNum)
    if not userinfo or userinfo == "" then
        return ""
    end

    return string.upper(Info_ValueForKey(userinfo, "cl_guid") or "")
end

local function read_file_all(path)
    local f = io.open(path, "r")
    if not f then
        return ""
    end
    local s = f:read("*all")
    f:close()
    return s or ""
end

-- Executes curl, returns (httpCode, decodedBody, err).
-- decodedBody may be nil when the response body is empty or not JSON.
local function executeCurlJsonWithHttpStatus(curl_cmd, body_file)
    local p = io.popen(curl_cmd .. " 2>&1")
    if not p then
        return nil, nil, "Failed to start curl"
    end

    local output = p:read("*all") or ""
    local ok, _, code = p:close()

    if type(ok) == "number" then
        code = ok
        ok = (code == 0)
    end

    if ok ~= true then
        output = trim(output)
        if output ~= "" then
            return nil, nil, output
        end
        return nil, nil, string.format("curl failed (exit=%s)", tostring(code))
    end

    local status = output:match("HTTPSTATUS:(%d%d%d)")
    local httpCode = tonumber(status)
    if not httpCode then
        return nil, nil, "Empty response (no HTTP status)"
    end

    local body = body_file and read_file_all(body_file) or ""
    local decoded = nil
    if json and body ~= "" then
        decoded = json.decode(body)
    end

    return httpCode, decoded, nil
end

local function post_register_request(etGuid, registrationToken)
    if not json then
        return nil, nil, "dkjson not available"
    end
    if AUTH_TOKEN == "" then
        return nil, nil, "API key is not configured"
    end

    local payload_json = json.encode({
        etGuid = etGuid,
        token = registrationToken
    })

    local temp_file = os.tmpname() .. ".json"
    local body_file = os.tmpname() .. ".out"
    local f = io.open(temp_file, "w")
    if not f then
        return nil, nil, "Failed to create temp file"
    end
    f:write(payload_json)
    f:close()

    local authToken = tostring(AUTH_TOKEN or "")

    -- Match pappabalance.lua Authorization header formatting.
    local curl_cmd = "curl -sS -o " .. shell_quote(body_file)
        .. " -w 'HTTPSTATUS:%{http_code}' -X POST -H " .. shell_quote("Authorization: Bearer " .. authToken)
        .. " -H 'Content-Type: application/json' --compressed --connect-timeout 2 --max-time 15"
        .. " --data-binary " .. shell_quote("@" .. temp_file) .. " " .. shell_quote(REGISTER_API_URL)

    local httpCode, decoded, err = executeCurlJsonWithHttpStatus(curl_cmd, body_file)

    -- Best-effort cleanup.
    os.remove(temp_file)
    os.remove(body_file)

    return httpCode, decoded, err
end

local function handle_register_command(clientNum, registrationToken)
    registrationToken = trim(registrationToken)
    if registrationToken == "" then
        say_player(clientNum, "^3Register:^7 usage: /register <token> (get your token from the stats website)")
        return
    end

    local etGuid = guid_for_client(clientNum)
    if etGuid == "" then
        say_player(clientNum, "^1Register failed:^7 could not read your GUID (cl_guid)")
        return
    end

    local httpCode, response, err = post_register_request(etGuid, registrationToken)
    if not httpCode then
        say_player(clientNum, "^1Register failed:^7 " .. tostring(err))
        log(string.format("register request failed for client %d: %s", clientNum, tostring(err)))
        return
    end

    if httpCode == 200 then
        local message = (type(response) == "table" and response.message) or "Registration successful!"
        say_player(clientNum, "^2Register:^7 " .. tostring(message))
        return
    end

    if httpCode == 401 then
        say_player(clientNum, "^1Register failed:^7 server configuration error (unauthorized). Contact an admin.")
        log("register request unauthorized (401) - check AUTH_TOKEN / backend ingest token")
        return
    end

    -- Backend returns { "error": "..." } with a user-friendly message for 400/404/409.
    local errorMessage = (type(response) == "table" and response.error) or string.format("HTTP %d", httpCode)
    say_player(clientNum, "^1Register failed:^7 " .. tostring(errorMessage))
end

function et_InitGame(levelTime, randomSeed, restart)
    reminderQueue, reminderRequests, connections = {}, {}, {}
    reminderPollAt = 0
    et.RegisterModname(modname .. " " .. version)
    local token, tokenError = load_api_key()
    AUTH_TOKEN = token or ""
    if AUTH_TOKEN == "" then
        log("API authentication unavailable: " .. tostring(tokenError))
    else
        log("API authentication configured")
    end
    log("loaded")
end

-- Connection reminders never read a network pipe on the game thread. Only
-- completed local files are inspected; curl owns the network timeout.
local function reminder_cleanup(request)
    for _, path in ipairs(request.files) do os.remove(path) end
end

local function reminder_connected(request)
    return connections[request.client] == request.connection
        and et.gentity_get(request.client, "pers.connected") == 2
        and guid_for_client(request.client) == request.guid
end

local function start_reminder(request)
    local base = os.tmpname()
    request.payload, request.body = base, base .. ".body"
    request.status, request.done = base .. ".status", base .. ".done"
    request.files = { request.payload, request.body, request.status, request.done }
    local file = io.open(request.payload, "w")
    if not file then reminder_cleanup(request); return end
    local written = file:write(json.encode({ etGuid = request.guid }))
    local closed = file:close()
    if not written or not closed then reminder_cleanup(request); return end
    local curl = "curl -sS --connect-timeout 2 --max-time 5 --max-filesize 4096 -X POST"
        .. " -H " .. shell_quote("Authorization: Bearer " .. AUTH_TOKEN)
        .. " -H 'Content-Type: application/json' --data-binary " .. shell_quote("@" .. request.payload)
        .. " -o " .. shell_quote(request.body) .. " -w '%{http_code}' " .. shell_quote(STATUS_API_URL)
        .. " > " .. shell_quote(request.status)
    local paths = {}
    for _, path in ipairs(request.files) do paths[#paths + 1] = shell_quote(path) end
    -- Detach all standard streams, including the shell's inherited input.
    -- Worker cleanup also handles map changes that unload this Lua VM.
    local command = "( " .. curl .. "; printf '%s' \"$?\" > " .. shell_quote(request.done)
        .. "; sleep 30; rm -f -- " .. table.concat(paths, " ")
        .. " ) </dev/null >/dev/null 2>&1 &"
    local result = os.execute(command)
    if result ~= true and result ~= 0 then reminder_cleanup(request); return end
    request.started = os.time()
    reminderRequests[#reminderRequests + 1] = request
end

function et_ClientConnect(clientNum, firstTime, isBot)
    -- A new identity object also rejects replies after same-GUID reconnects.
    connections[clientNum] = {}
    reminderQueue[clientNum] = nil
    if isBot == 1 then connections[clientNum] = nil end
end

function et_ClientBegin(clientNum)
    if not connections[clientNum] or AUTH_TOKEN == "" or not json
        or package.config:sub(1, 1) == "\\"
        or trap_Cvar_Get("pappa_register_reminders") == "0" then return end
    local guid = guid_for_client(clientNum)
    if #guid ~= 32 or guid:find("[^%x]") then return end
    reminderQueue[clientNum] = { client = clientNum, guid = guid,
        connection = connections[clientNum], due = os.time() + 10 }
end

function et_ClientDisconnect(clientNum)
    connections[clientNum], reminderQueue[clientNum] = nil, nil
end

function et_RunFrame(levelTime)
    if levelTime < reminderPollAt then return end
    reminderPollAt = levelTime + 200
    local now = os.time()
    for index = #reminderRequests, 1, -1 do
        local request = reminderRequests[index]
        local done = read_file_all(request.done)
        if done ~= "" or now - request.started > 10 then
            if done == "0" and read_file_all(request.status) == "200" and reminder_connected(request) then
                local response = json.decode(read_file_all(request.body))
                if type(response) == "table" and response.registered == false then
                    say_player(request.client, "^3Pappaliiga:^7 GUID:iasi ei ole yhdistetty Discord-tiliisi. Kirjaudu Discordilla osoitteessa https://et.aukko.net ja kopioi sivun /register-komento pelikonsoliin.")
                end
            end
            -- Leave running workers' files alone until their timeout/cleanup.
            if done ~= "" then reminder_cleanup(request) end
            table.remove(reminderRequests, index)
        end
    end
    for client, request in pairs(reminderQueue) do
        if now >= request.due then
            if reminder_connected(request) and #reminderRequests < 4 then
                start_reminder(request)
                reminderQueue[client] = nil
            elseif not reminder_connected(request) then
                reminderQueue[client] = nil
            end
        end
    end
end

function et_ClientCommand(clientNum, command)
    local cmd = string.lower(tostring(et.trap_Argv(0) or ""))

    -- Console command: /register <token>
    if cmd == "register" then
        handle_register_command(clientNum, et.ConcatArgs(1) or "")
        return 1
    end

    -- Chat command: !register <token>
    if cmd == "say" or cmd == "say_team" or cmd == "say_buddy" then
        local msg = trim(et.ConcatArgs(1) or "")
        if starts_with(msg, "!register") then
            handle_register_command(clientNum, msg:sub(#"!register" + 1))
            -- Swallow command so the token doesn't appear in chat.
            return 1
        end
    end

    return 0
end
