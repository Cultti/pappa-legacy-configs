-- Opt-in, bounded live telemetry. Keep local transport on tmpfs; no HTTP in game frames.
local ok, json = pcall(require, 'dkjson')
local enabled, next_write, now, sequence = false, 0, 0, 0
local session, events, generations, bots = '', {}, {}, {}
local last_cost,max_cost,write_failures=0,0,0
local path = os.getenv('BROADCAST_SOURCE_FILE') or '/runtime/source.json'
local max_events = 256
-- Non-archived engine cvars survive Lua reloads and stopwatch half changes.
-- A new server process has no identity; a new map or completed match gets a new ID.
local function match_state()
    local function value(key) return et.trap_Cvar_Get('pappa_broadcast_' .. key) or '' end
    local function put(key,v) v=tostring(v); if value(key)~=v then et.trap_Cvar_Set('pappa_broadcast_' .. key,v) end end
    local map=et.trap_Cvar_Get('mapname')
    local state=tonumber(et.trap_Cvar_Get('gamestate'))
    local round=tonumber(et.trap_Cvar_Get('g_currentRound')) or 0
    local boot=value('boot')
    if boot=='' then boot=session;put('boot',boot) end
    local complete=value('match_complete')=='1'
    if value('match_id')=='' or value('match_map')~=map or
        (complete and (state==1 or state==2 or (state==0 and round==0))) then
        local counter=(tonumber(value('match_counter')) or 0)+1
        put('match_counter',counter);put('match_id',boot .. ':' .. counter)
        put('match_map',map);put('match_complete','0');put('playing_round','');put('last_state','')
        complete=false
    end
    if state==3 and value('last_state')~='3' then
        local stopwatch=tonumber(et.trap_Cvar_Get('g_gametype'))==3
        if not stopwatch or value('playing_round')=='1' or (value('last_state')=='' and round==0) then
            complete=true;put('match_complete','1')
        end
    end
    if state==0 then put('playing_round',round) end
    put('last_state',state or -1)
    return value('match_id'),complete
end
local function get(slot, field, index)
    local success, value = pcall(et.gentity_get, slot, field, index)
    if success then return value end
end
local function player(slot)
    if type(slot) ~= 'number' or slot < 0 or slot >= 64 or get(slot, 'pers.connected') ~= 2 then return nil end
    local team = get(slot, 'sess.sessionTeam') or 3
    if team ~= 1 and team ~= 2 then return nil end
    return {slot=slot, generation=generations[slot] or 1, name=get(slot, 'pers.netname') or '', team=team,
        health=get(slot, 'health') or 0, flags=get(slot, 'ps.pm_flags') or 0,
        position=get(slot, 'r.currentOrigin'), angles=get(slot, 'ps.viewangles')}
end
local function population()
    local humans,total=0,0
    for slot=0,math.min(63,(tonumber(et.trap_Cvar_Get('sv_maxclients')) or 64)-1) do
        local team=get(slot,'sess.sessionTeam')
        if get(slot,'pers.connected')==2 and (team==1 or team==2) then
            total=total+1
            local flags=tonumber(get(slot,'r.svFlags')) or 0
            local info=et.trap_GetUserinfo and et.trap_GetUserinfo(slot) or ''
            local password=et.trap_Cvar_Get('sv_etltv_password') or ''
            local tv=et.Info_ValueForKey and tonumber(et.Info_ValueForKey(info,'protocol'))==284
                and password~='' and et.Info_ValueForKey(info,'masterpassword')==password
            if not bots[slot] and (flags & 8)==0 and not tv then humans=humans+1 end
        end
    end
    return humans,total
end
local function record(kind, actor, victim, value, mod)
    if not enabled then return end
    sequence = sequence + 1
    local a, v = player(actor), player(victim)
    events[#events+1] = {seq=sequence, timeMs=now, type=kind, actorSlot=a and actor or -1,
        actorGeneration=a and a.generation, actorName=a and a.name, actorTeam=a and a.team,
        victimSlot=v and victim or -1, value=value, mod=mod,
        teamkill=(a and v and a.team == v.team) or false,
        warmup=tonumber(et.trap_Cvar_Get('gamestate')) ~= 0}
    if #events > max_events then table.remove(events, 1) end
end
function et_InitGame(levelTime, seed, restart)
    enabled = ok and os.getenv('BROADCAST_ENABLED') == 'true'
    if not enabled then
        if os.getenv('BROADCAST_ENABLED')=='true' and not ok then et.G_Print('PappaBroadcast disabled: dkjson is not available\n') end
        return
    end
    et.RegisterModname('PappaBroadcast 0.1.0')
    if et.FindSelf then et.trap_Cvar_Set('pappa_broadcast_vm', tostring(et.FindSelf())) end
    now, next_write, sequence, events, generations, bots = levelTime, 0, 0, {}, {}, {}
    last_cost,max_cost,write_failures=0,0,0
    local server = (os.getenv('BROADCAST_SERVER_ID') or 'test'):gsub('[^%w_-]', ''):sub(1,32)
    session = server .. '-' .. tostring(os.time()) .. '-' .. tostring(et.trap_Milliseconds()) .. '-' .. tostring(seed)
    -- Publish only an opaque session ID; the delayed relay receives it on the same timeline.
    et.trap_SendConsoleCommand(et.EXEC_APPEND, 'sets pappa_broadcast_session "' .. session .. '"\n')
end
function et_IPCReceive(vmnumber,message)
    if not enabled or type(message)~='string' or #message>4096 then return end
    local event,_,err=json.decode(message)
    local labels={obj_planted=true,obj_defused=true,obj_destroyed=true,obj_secured=true,obj_taken=true,obj_flag_captured=true,obj_repaired=true,obj_returned=true}
    if err or type(event)~='table' or event.kind~='broadcast_objective' or not labels[event.label] or type(event.guid)~='string' then return end
    -- IPC is local to trusted Lua VMs. Require an exact, unique connected identity.
    local actor=nil
    for slot=0,math.min(63,(tonumber(et.trap_Cvar_Get('sv_maxclients')) or 64)-1) do
        if player(slot) then
            local guid=et.Info_ValueForKey(et.trap_GetUserinfo(slot) or '', 'cl_guid') or ''
            if guid~='' and guid:upper()==event.guid:upper() then if actor then return end; actor=slot end
        end
    end
    if actor then
        record('objective',actor,nil,1,nil)
        events[#events].label=event.label
    end
end
function et_ClientConnect(slot, firstTime, isBot)
    generations[slot] = (generations[slot] or 0) + 1
    bots[slot] = isBot==1
end
function et_Obituary(victim, attacker, mod) record('kill', attacker, victim, 1, mod); return 0 end
function et_Damage(victim, attacker, damage, flags, mod)
    if damage and damage > 0 then record('damage', attacker, victim, math.min(damage,1000), mod) end
    return 0
end
function et_RunFrame(levelTime)
    now = levelTime
    if not enabled or now < next_write then return end
    next_write = now + 250
    local started = et.trap_Milliseconds()
    local roster = {}
    for slot=0,math.min(63,(tonumber(et.trap_Cvar_Get('sv_maxclients')) or 64)-1) do
        local p = player(slot); if p then roster[#roster+1] = p end
    end
    local match_id,match_complete=match_state()
    local human_players,total_players=population()
    local body = json.encode({schema=1,session=session,map=et.trap_Cvar_Get('mapname'),timeMs=now,
        matchId=match_id,matchComplete=match_complete,
        humanPlayers=human_players,activePlayers=total_players,
        gamestate=tonumber(et.trap_Cvar_Get('gamestate')),round=tonumber(et.trap_Cvar_Get('g_currentRound')),
        paused=et.CS_SERVERTOGGLES and (((tonumber(et.trap_GetConfigstring(et.CS_SERVERTOGGLES)) or 0) & 16)~=0) or false,
        sequence=sequence,events=events,players=roster,lastFlushMs=last_cost,maxFlushMs=max_cost,writeFailures=write_failures})
    if #body > 262144 then return end
    local f = io.open(path .. '.tmp', 'w')
    if f then
        local written=f:write(body); f:close()
        if not written or not os.rename(path .. '.tmp', path) then write_failures=write_failures+1 end
    else write_failures=write_failures+1 end
    local cost = et.trap_Milliseconds() - started
    last_cost=cost;max_cost=math.max(max_cost,cost)
    et.trap_Cvar_Set('pappa_broadcast_last_flush_ms', tostring(cost))
end
