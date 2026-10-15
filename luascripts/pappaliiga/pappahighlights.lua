-- Local presence evidence for the intake container. No HTTP or credentials in Lua.
local json_ok, json = pcall(require, 'dkjson')
local enabled, next_write, sequence = false, 0, 0
local boot, session_start, last_busy = '', 0, 0
local bots = {}
-- The managed recorder is controlled through combinedfixes.lua's console bridge.
-- Fixed commands only: no shell arguments, RCON credentials or HTTP in this module.
local match_recording, previous_state, playing_round, stop_at = false, nil, nil, nil
local function recorder(command)
    et.trap_SendConsoleCommand(et.EXEC_APPEND, 'etltv ' .. command .. '\n')
    et.trap_Cvar_Set('pappa_highlight_recorder_armed', command == 'start' and '1' or '0')
end
local function recording_tick()
    if not match_recording then return end
    local state = tonumber(et.trap_Cvar_Get('gamestate'))
    local round = tonumber(et.trap_Cvar_Get('g_currentRound'))
    local now_ms = et.trap_Milliseconds()
    if state ~= previous_state then
        if state == et.GS_WARMUP and round == 0 then
            -- New match, aborted countdown, or map change: close any previous demo.
            stop_at = nil
            recorder('stop')
        elseif state == et.GS_WARMUP_COUNTDOWN and round == 0 then
            stop_at = nil
            recorder('start')
        elseif state == et.GS_PLAYING then
            stop_at = nil
            -- Recover if Lua/container was loaded after the countdown.
            if et.trap_Cvar_Get('pappa_highlight_recorder_armed') ~= '1' then recorder('start') end
        elseif state == et.GS_INTERMISSION and
            ((previous_state == et.GS_PLAYING and playing_round == 1) or (previous_state == nil and round == 0)) then
            -- Snapshot the round while playing: g_currentRound flips at intermission.
            -- Retain a short tail, then finalize even when players stay connected.
            stop_at = now_ms + 5000
        end
        previous_state = state
    end
    if state == et.GS_PLAYING then playing_round = round end
    if stop_at and now_ms >= stop_at then
        stop_at = nil
        recorder('stop')
    end
end
local function humans()
    local count = 0
    for client=0,(tonumber(et.trap_Cvar_Get('sv_maxclients')) or 64)-1 do
        if tonumber(et.gentity_get(client, 'pers.connected')) == 2 then
            local flags = tonumber(et.gentity_get(client, 'r.svFlags')) or 0
            local info = et.trap_GetUserinfo(client) or ''
            local master = et.trap_Cvar_Get('sv_etltv_password') or ''
            -- Only authenticated protocol-284 relays are excluded. Never persist userinfo/passwords.
            local tv = tonumber(et.Info_ValueForKey(info, 'protocol')) == 284 and master ~= ''
                and et.Info_ValueForKey(info, 'masterpassword') == master
            if not bots[client] and math.floor(flags / 8) % 2 == 0 and not tv then count = count + 1 end
        end
    end
    return count
end
function et_InitGame(levelTime, randomSeed, restart)
    enabled = os.getenv('HIGHLIGHT_AUTOMATION_ENABLED') == 'true' and json_ok
    if not enabled then return end
    et.RegisterModname('PappaHighlights 1.1')
    match_recording = os.getenv('HIGHLIGHT_ETLTV_MATCH_CONTROL') == 'true'
    previous_state, playing_round, stop_at = nil, nil, nil
    local now = os.time()
    boot = tostring(now) .. '-' .. tostring(et.trap_Milliseconds()) .. '-' .. tostring(randomSeed)
    session_start = tonumber(et.trap_Cvar_Get('pappa_highlight_session_start')) or 0
    last_busy = tonumber(et.trap_Cvar_Get('pappa_highlight_last_busy')) or 0
    next_write, sequence = 0, 0
end
function et_ClientConnect(client, firstTime, isBot) bots[client] = isBot == 1 end
function et_ClientDisconnect(client) bots[client] = nil end
function et_RunFrame(levelTime)
    if not enabled then return end
    recording_tick()
    if levelTime < next_write then return end
    next_write = levelTime + 15000
    local now, count = os.time(), humans()
    local playing = tonumber(et.trap_Cvar_Get('gamestate')) == et.GS_PLAYING
    if playing and count > 3 and (session_start == 0 or now-last_busy > 3600) then session_start = now end
    if count > 3 then last_busy = now end
    if count <= 3 and last_busy > 0 and now-last_busy > 3600 then session_start = 0 end
    et.trap_Cvar_Set('pappa_highlight_session_start', tostring(session_start))
    et.trap_Cvar_Set('pappa_highlight_last_busy', tostring(last_busy))
    sequence = sequence + 1
    local file = os.getenv('HIGHLIGHT_PRESENCE_FILE') or '/automation/presence.json'
    local temporary = file .. '.tmp'
    local output = io.open(temporary, 'w')
    if not output then return end
    local ok = output:write(json.encode({observedAt=now, humans=count, sessionStartedAt=session_start,
        bootId=boot, sequence=sequence, playing=playing}))
    local closed = output:close()
    if ok and closed then os.rename(temporary, file) else os.remove(temporary) end
end
