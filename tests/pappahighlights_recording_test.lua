-- Run with Lua 5.4. No game, shell, recorder or network access.
local vars, commands, milliseconds, current_payload = {}, {}, 0, nil
local enabled, control = true, true
package.preload.dkjson=function()return{encode=function(value)current_payload=value;return 'json' end}end
os.getenv=function(name)
    if name=='HIGHLIGHT_AUTOMATION_ENABLED' then return enabled and 'true' or 'false' end
    if name=='HIGHLIGHT_ETLTV_MATCH_CONTROL' then return control and 'true' or 'false' end
    if name=='HIGHLIGHT_PRESENCE_FILE' then return '/presence.json' end
end
os.time=function()return 1000+math.floor(milliseconds/1000) end
io.open=function()return{write=function(self)return self end,close=function()return true end}end
os.rename=function()return true end
et={GS_WARMUP=0,GS_WARMUP_COUNTDOWN=1,GS_PLAYING=2,GS_INTERMISSION=3,EXEC_APPEND=2,
    RegisterModname=function()end,trap_Milliseconds=function()return milliseconds end,
    trap_Cvar_Get=function(name)return vars[name] or '' end,
    trap_Cvar_Set=function(name,value)vars[name]=value end,
    trap_SendConsoleCommand=function(mode,command)assert(mode==et.EXEC_APPEND);commands[#commands+1]=command end}
local function load(state,round)
    vars.gamestate=tostring(state);vars.g_currentRound=tostring(round);vars.sv_maxclients='0'
    assert(loadfile('luascripts/pappaliiga/pappahighlights.lua'))()
    et_InitGame(0,123,0)
end
local function frame(state,round,elapsed)
    milliseconds=milliseconds+(elapsed or 1)
    vars.gamestate=tostring(state);vars.g_currentRound=tostring(round)
    et_RunFrame(milliseconds)
end
local function last(command)assert(commands[#commands]=='etltv '..command..'\n')end
load(et.GS_WARMUP,0);frame(et.GS_WARMUP,0);last('stop')
frame(et.GS_WARMUP_COUNTDOWN,0);last('start')
local started=#commands
frame(et.GS_WARMUP_COUNTDOWN,0);assert(#commands==started,'no duplicate start every frame')
frame(et.GS_PLAYING,0)
frame(et.GS_INTERMISSION,1);frame(et.GS_INTERMISSION,1,6000)
assert(#commands==started,'round-one intermission does not stop recording after cvar flips')
-- Lua VM resets between rounds; the recorder remains armed in a non-archived cvar.
load(et.GS_WARMUP,1);frame(et.GS_WARMUP,1);assert(#commands==started)
frame(et.GS_WARMUP_COUNTDOWN,1);frame(et.GS_PLAYING,1)
frame(et.GS_INTERMISSION,0);frame(et.GS_INTERMISSION,0,4999)
assert(#commands==started,'retain the intermission tail')
frame(et.GS_INTERMISSION,0,1);last('stop')
local stopped=#commands
frame(et.GS_INTERMISSION,0,60000);assert(#commands==stopped,'stays stopped while players linger')
frame(et.GS_WARMUP,0);last('stop');frame(et.GS_WARMUP_COUNTDOWN,0);last('start')
frame(et.GS_WARMUP,0);last('stop') -- aborted countdown
-- New playing state cancels a pending stop from the previous match.
frame(et.GS_PLAYING,1);frame(et.GS_INTERMISSION,0)
frame(et.GS_WARMUP_COUNTDOWN,0);local resumed=#commands
frame(et.GS_PLAYING,0,6000);assert(#commands==resumed,'old timer cannot stop a new game')
-- Recovery when the module starts during play, without a countdown event.
vars.pappa_highlight_recorder_armed='0';load(et.GS_PLAYING,1);frame(et.GS_PLAYING,1);last('start')
frame(et.GS_INTERMISSION,0);frame(et.GS_INTERMISSION,0,5000);last('stop')
-- Loading during the completed match's intermission still finalizes; halftime does not.
load(et.GS_INTERMISSION,0);frame(et.GS_INTERMISSION,0);local recovering=#commands
frame(et.GS_INTERMISSION,0,5000);assert(#commands==recovering+1);last('stop')
load(et.GS_INTERMISSION,1);frame(et.GS_INTERMISSION,1);local halftime=#commands
frame(et.GS_INTERMISSION,1,6000);assert(#commands==halftime)
-- Abort/restart closes an interrupted match without requiring two completed rounds.
frame(et.GS_PLAYING,0);frame(et.GS_WARMUP,0);last('stop')
local before=#commands
control=false;load(et.GS_WARMUP,0);frame(et.GS_WARMUP,0);frame(et.GS_WARMUP_COUNTDOWN,0)
assert(#commands==before,'server-demo mode never controls ETLTV')
control=true;enabled=false;load(et.GS_WARMUP,0);frame(et.GS_WARMUP,0)
assert(#commands==before,'disabled automation never controls ETLTV')
print('pappahighlights recording: all checks passed')