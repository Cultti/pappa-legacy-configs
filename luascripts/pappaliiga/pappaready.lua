-- PappaReady - last-ready-up reporting, extracted from pappastats.lua.
-- Run alongside Oksii's stats.lua, replacing pappastats.lua.
-- Requires dkjson and curl on a Linux ET: Legacy server.
-- Token: STATS_API_TOKEN environment variable.
-- Server identity: pappa_stats_server_id (defaults to sv_hostname).

local modname = "PappaReady"
local version = "1.1"
local READY_UP_URL = "https://et.aukko.net/api/ready-ups"
local EVENT_SEQUENCE_CVAR = "pappa_ready_event_sequence"
local json_ok, json = pcall(require, "dkjson")
if not json_ok then json = nil end

local authToken = ""
local maxClients = 64
local currentGameState = et.GS_INITIALIZE
local readyUps = {}
local pendingReadyUp = nil
local readySequence = 0
local holdout
local messages = {
    "ON LAHOMUNA!",
    "ON MÄTÄ PERUNA!",
    "ON HAPAN KURKKU!",
    "ON LÖYSÄ MAKARONI!",
    "ON MÄRKÄ SUKKA!",
    "ON HAISEVA PIERU!",
    "ON PIERUPERSE!",
    "ON LÖLLÖMAHA!",
    "ON NÖSSÖ!",
    "ON MAMMANPOIKA!",
    "ON TÖLLÖTIN!",
    "ON PÖLLÖPÄÄ!",
    "ON HÖLMÖLÄINEN!",
    "ON VELLIPÖKSY!",
    "ON PUPUPÖKSY!",
    "ON ITKUPILLI!",
    "ON NENÄNKAIVAJA!",
    "ON RÄKÄNOKKA!",
    "ON KAKKAHOUSU!",
    "ON PÖKSYNPÄÄ!",
    "ON MÄTÄ TOMAATTI!",
    "ON KUIVUNUT NAKKI!",
    "ON LÖYSÄ NAKKI!",
    "ON PULLEA PULLA!",
    "ON KÄVELEVÄ PERUNA!",
    "JÄI NUOLEMAAN NÄPPEJÄÄN!",
    "JÄI KUIN NALLI KALLIOLLE!",
    "SAA JÄÄNNÖKSET!",
    "JOUTUU SIIVOAMAAN!",
    "SAMMUTTAA VALOT!",
    "PESEE VESSAT!",
}

local function log(message)
    et.G_Print(string.format("^2[%s]^7 %s\n", modname, tostring(message)))
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function load_api_key()
    local token = trim(os.getenv("STATS_API_TOKEN"))
    if token == "" then return nil, "STATS_API_TOKEN is not configured." end
    if token:find("[%c]") then return nil, "STATS_API_TOKEN contains control characters." end
    return token
end

local function server_id()
    local configured = trim(et.trap_Cvar_Get("pappa_stats_server_id"))
    if configured ~= "" then return configured end
    return tostring(et.trap_Cvar_Get("sv_hostname") or "")
end

local function guid_for_client(client)
    if type(client) ~= "number" or client < 0 or client >= maxClients then return "" end
    local userinfo = et.trap_GetUserinfo(client)
    if not userinfo or userinfo == "" then return "" end
    return tostring(et.Info_ValueForKey(userinfo, "cl_guid") or ""):upper()
end

local function is_ready(entry)
    local team = tonumber(et.gentity_get(entry.client, "sess.sessionTeam"))
    return guid_for_client(entry.client) == entry.guid
        and tonumber(et.gentity_get(entry.client, "pers.connected")) == 2
        and (team == 1 or team == 2)
        and tonumber(et.gentity_get(entry.client, "pers.ready")) == 1
end

local function clear_ready_ups()
    holdout = nil
    readyUps = {}
    pendingReadyUp = nil
end

-- Measure the continuous stretch with exactly one unready player.
local function observe_holdout()
    local candidate, readyCount = nil, 0
    for client = 0, maxClients - 1 do
        if tonumber(et.gentity_get(client, "pers.connected")) == 2 then
            local team = tonumber(et.gentity_get(client, "sess.sessionTeam"))
            if team == 1 or team == 2 then
                if tonumber(et.gentity_get(client, "pers.ready")) == 1 then
                    readyCount = readyCount + 1
                elseif candidate ~= nil then
                    holdout = nil
                    return
                else
                    candidate = client
                end
            end
        end
    end
    if candidate == nil or readyCount == 0 then holdout = nil; return end
    local guid = guid_for_client(candidate)
    if not holdout or holdout.client ~= candidate or holdout.guid ~= guid then
        holdout = { client = candidate, guid = guid, since = et.trap_Milliseconds() }
    end
end

local function process_ready_ups()
    local state = tonumber(et.trap_Cvar_Get("gamestate"))
    if state ~= et.GS_WARMUP and state ~= et.GS_WARMUP_COUNTDOWN then return end
    -- ClientCommand runs before ET applies pers.ready. Check the previous
    -- command on the next callback so rejected commands never count.
    if pendingReadyUp then
        local candidate = pendingReadyUp
        pendingReadyUp = nil
        if is_ready(candidate) then readyUps[candidate.guid] = candidate end
    end
    for guid, entry in pairs(readyUps) do
        if not is_ready(entry) then readyUps[guid] = nil end
    end
end

local function post_ready_up(payload)
    -- The same JSON/event ID is used for every curl retry. Clean up only
    -- after curl finishes, so retries cannot outlive their payload file.
    local path = os.tmpname()
    local file = io.open(path, "w")
    if not file then
        os.remove(path)
        return false, "cannot write request payload"
    end
    local written, writeError = file:write(payload)
    local closed, closeError = file:close()
    if not written or not closed then
        os.remove(path)
        return false, writeError or closeError or "cannot save request payload"
    end
    local command = "( curl --fail -X POST -H " .. shell_quote("Authorization: Bearer " .. authToken)
        .. " -H 'Content-Type: application/json' --data-binary " .. shell_quote("@" .. path)
        .. " --compressed --connect-timeout 2 --max-time 10"
        .. " --retry 3 --retry-delay 1 --retry-max-time 15 --silent --output /dev/null "
        .. shell_quote(READY_UP_URL) .. "; rm -f " .. shell_quote(path) .. " ) >/dev/null 2>&1 &"
    local result = os.execute(command)
    local started = result == true or result == 0
    if not started then os.remove(path) end
    return started, "cannot start background curl"
end

local function send_last_ready_up()
    local last = nil
    for _, entry in pairs(readyUps) do
        if not last or entry.sequence > last.sequence then last = entry end
    end
    if not last then return end
    if last.waitMs ~= nil then
        local name = tostring(et.gentity_get(last.client, "pers.netname") or "")
            :gsub('[%c"\\]', "")
        et.trap_SendServerCommand(-1, 'chat "' .. name .. " ^1"
            .. messages[math.random(#messages)] .. '"')
    end
    if not json or authToken == "" then
        log("Last ready-up could not be sent: JSON or API authentication unavailable")
        return
    end
    local id = server_id()
    local hash = 0
    for i = 1, #id do hash = (hash * 31 + id:byte(i)) % 4294967296 end
    -- Persist the sequence across Lua VM restarts to avoid reusing event IDs.
    local sequence = (tonumber(et.trap_Cvar_Get(EVENT_SEQUENCE_CVAR)) or 0) + 1
    et.trap_Cvar_Set(EVENT_SEQUENCE_CVAR, tostring(sequence))
    local payload = json.encode({
        eventId = string.format("ready-%08x-%d-%d-%d", hash, os.time(), et.trap_Milliseconds(), sequence),
        playerGuid = last.guid,
        readyAtUnix = last.atUnix,
        waitMs = last.waitMs,
        countdownAtUnix = os.time(),
        serverId = id,
        mapName = tostring(et.trap_Cvar_Get("mapname") or ""),
        round = (tonumber(et.trap_Cvar_Get("g_currentRound")) or 0) + 1
    })
    local started, err = post_ready_up(payload)
    log("Last ready-up POST " .. (started and "started: " .. last.guid or "failed: " .. tostring(err)))
end

function et_InitGame(levelTime, randomSeed, restart)
    et.RegisterModname(modname .. " " .. version)
    local token, err = load_api_key()
    authToken = token or ""
    if authToken == "" then log("Authentication unavailable: " .. tostring(err)) end
    if not json then log("dkjson unavailable; ready-up reporting disabled") end
    maxClients = tonumber(et.trap_Cvar_Get("sv_maxclients")) or 64
    currentGameState = tonumber(et.trap_Cvar_Get("gamestate")) or et.GS_INITIALIZE
    clear_ready_ups()
    readySequence = 0
    log("Loaded " .. version)
end

function et_RunFrame(gameFrameLevelTime)
    local state = tonumber(et.trap_Cvar_Get("gamestate"))
    if state == nil then return end
    if state == et.GS_WARMUP and state ~= currentGameState then clear_ready_ups() end
    process_ready_ups()
    if state == et.GS_WARMUP_COUNTDOWN and currentGameState == et.GS_WARMUP then
        send_last_ready_up()
        clear_ready_ups()
    elseif state ~= et.GS_WARMUP and state ~= et.GS_WARMUP_COUNTDOWN then
        clear_ready_ups()
    end
    if state == et.GS_WARMUP then observe_holdout() end
    currentGameState = state
end

function et_ClientCommand(client, command)
    process_ready_ups()
    if tonumber(et.trap_Cvar_Get("gamestate")) ~= et.GS_WARMUP then return 0 end
    local cmd = tostring(command or ""):lower()
    if cmd ~= "ready" and cmd ~= "readytoggle" then return 0 end
    local guid = guid_for_client(client)
    if #guid ~= 32 or not guid:match("^%x+$") then return 0 end
    local team = tonumber(et.gentity_get(client, "sess.sessionTeam"))
    if tonumber(et.gentity_get(client, "pers.connected")) ~= 2
        or (team ~= 1 and team ~= 2)
        or tonumber(et.gentity_get(client, "pers.ready")) ~= 0 then return 0 end
    observe_holdout()
    local waitMs
    if holdout and holdout.client == client and holdout.guid == guid then
        waitMs = math.max(0, et.trap_Milliseconds() - holdout.since)
    end
    readySequence = readySequence + 1
    pendingReadyUp = { client = client, guid = guid, sequence = readySequence, atUnix = os.time(), waitMs = waitMs }
    return 0 -- Let ET and other Lua modules handle the command normally.
end

function et_ClientDisconnect(client)
    if holdout and holdout.client == client then holdout = nil end
    for guid, entry in pairs(readyUps) do
        if entry.client == client then readyUps[guid] = nil end
    end
    if pendingReadyUp and pendingReadyUp.client == client then pendingReadyUp = nil end
end
