-- Private relay-only bridge: applies bounded decisions exclusively to the named camera viewer.
local ok, json = pcall(require, 'dkjson')
local enabled, next_tick, sequence, applied, rejected = false, 0, 0, 0, ''
local root = os.getenv('BROADCAST_RUNTIME') or '/runtime'
local viewer_name = os.getenv('BROADCAST_VIEWER_NAME') or 'BroadcastCamera'
local function safe(fn, ...) local success,value=pcall(fn,...); if success then return value end end
local function master(slot, field, index) return safe(et.ps_get,slot,field,index) end
local function info(slot)
    local text=et.trap_GetConfigstring(et.CS_PLAYERS+slot) or ''
    return et.Info_ValueForKey(text,'n'), tonumber(et.Info_ValueForKey(text,'t'))
end
local function read_command()
    local f=io.open(root..'/command.json','r'); if not f then return nil end
    local text=f:read(32769); f:close(); if #text>32768 then return nil end
    local value,_,err=json.decode(text); if err or type(value)~='table' then return nil end
    return value
end
function et_InitGame(levelTime,seed,restart)
    enabled=ok and os.getenv('BROADCAST_ENABLED')=='true'
    if enabled then et.RegisterModname('PappaBroadcastTV 0.1.0') end
    next_tick,sequence,applied,rejected=0,0,0,''
end
function et_RunFrame(levelTime)
    if not enabled or levelTime<next_tick then return end
    next_tick=levelTime+100
    local session=et.Info_ValueForKey(et.trap_GetConfigstring(et.CS_SERVERINFO) or '', 'pappa_broadcast_session') or ''
    local paused=et.CS_SERVERTOGGLES and (((tonumber(et.trap_GetConfigstring(et.CS_SERVERTOGGLES)) or 0) & 16)~=0) or false
    local intermission=safe(et.level_get,'intermission')==1
    local roster={}
    for slot=0,63 do
        local health=master(slot,'ps.stats',0)
        local name,team=info(slot)
        if health~=nil and (team==1 or team==2) then
            roster[#roster+1]={slot=slot,name=name,team=team,health=health,
                flags=master(slot,'ps.pm_flags') or 0, commandTime=master(slot,'ps.commandTime')}
        end
    end
    local viewers={}
    for slot=0,math.min(63,(tonumber(et.trap_Cvar_Get('sv_maxclients')) or 64)-1) do
        if safe(et.gclient_get,slot,'pers.connected')==2 and safe(et.gclient_get,slot,'pers.netname')==viewer_name then
            viewers[#viewers+1]=slot
        end
    end
    local command=read_command()
    if command and type(command.id)=='number' and command.id>applied then
        local valid=command.session==session and type(command.slot)=='number' and command.slot%1==0 and command.slot>=0 and command.slot<64
            and type(command.cutTimeMs)=='number' and type(command.expiresMs)=='number'
        if not valid then rejected='invalid_or_session'
        elseif levelTime>command.expiresMs then rejected='expired'; applied=command.id
        elseif levelTime>=command.cutTimeMs and #viewers==1 and not paused and not intermission then
            local name,team=info(command.slot)
            local health=master(command.slot,'ps.stats',0) or 0
            local flags=master(command.slot,'ps.pm_flags') or 0
            if name==command.name and team==command.team and health>0 and (flags & 16384)==0 then
                et.gclient_set(viewers[1],'sess.spectatorClient',command.slot)
                et.gclient_set(viewers[1],'sess.spectatorState',2)
                applied=command.id; rejected=''
            else rejected='target_unavailable'; applied=command.id end
        end
    end
    local viewer=viewers[1]
    sequence=sequence+1
    local body=json.encode({schema=1,sequence=sequence,session=session,timeMs=levelTime,
        queueSeconds=safe(et.level_get,'queueSeconds'),map=safe(et.level_get,'rawmapname'),paused=paused,intermission=intermission,
        players=roster,viewerCount=#viewers,viewerSlot=viewer,appliedId=applied,rejected=rejected,
        followedSlot=viewer and safe(et.gclient_get,viewer,'sess.spectatorClient'),
        spectatorState=viewer and safe(et.gclient_get,viewer,'sess.spectatorState')})
    local f=io.open(root..'/relay.json.tmp','w')
    if f then f:write(body); f:close(); os.rename(root..'/relay.json.tmp',root..'/relay.json') end
end
