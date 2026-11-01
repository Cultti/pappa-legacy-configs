local json=require('dkjson')
local output,clock= nil,100
local vars={gamestate='0',sv_maxclients='2',mapname='oasis',g_currentRound='0'}
local fields={['pers.connected']=2,['sess.sessionTeam']=1,['pers.netname']='Bot1',health=100,['ps.pm_flags']=0}
local realgetenv=os.getenv
os.getenv=function(k)if k=='BROADCAST_ENABLED' then return 'true' end return nil end
io.open=function()return{write=function(_,body)output=json.decode(body)end,close=function()end}end
os.rename=function()return true end
et={EXEC_APPEND=2,RegisterModname=function()end,trap_Cvar_Get=function(k)return vars[k] or ''end,
trap_Cvar_Set=function(k,v)vars[k]=v end,trap_SendConsoleCommand=function()end,trap_Milliseconds=function()return clock end,
gentity_get=function(slot,field)if field=='sess.sessionTeam' then return slot+1 end return fields[field]end}
assert(loadfile('luascripts/pappaliiga/pappabroadcast.lua'))()
et_InitGame(0,123,0);et_ClientConnect(0,1,1);et_RunFrame(100)
assert(output.session and output.timeMs==100)
assert(et_Damage(1,0,30,0,1)==0,'must not intercept damage')
assert(et_Obituary(1,0,1)==0,'must not intercept deaths')
et_RunFrame(400)
assert(#output.events==2 and output.events[2].type=='kill')
assert(output.events[1].timeMs==100,'snapshot timeline, not wall clock')
assert(output.events[1].warmup==false and output.events[1].teamkill==false)
for n=1,300 do et_Damage(1,0,10,0,1) end
et_RunFrame(700);assert(#output.events==256,'bounded event history')
assert(output.sequence==302)
et.trap_GetUserinfo=function(slot)return slot==0 and 'GUID-A' or 'GUID-B'end
et.Info_ValueForKey=function(text,key)return text end
et_IPCReceive(1,json.encode({kind='broadcast_objective',label='obj_defused',guid='GUID-A'}))
et_RunFrame(1000);assert(output.sequence==303 and output.events[#output.events].type=='objective')
assert(output.events[#output.events].timeMs==700,'objective uses snapshot clock, not Stats clock')
et_IPCReceive(1,'not JSON');et_IPCReceive(1,json.encode({kind='broadcast_objective',label='obj_defused',guid='MISSING'}))
et_RunFrame(1300);assert(output.sequence==303,'ambiguous or missing actors are not fabricated')
local first=output.matchId
vars.gamestate='3';et_RunFrame(1600);assert(output.matchComplete==true)
vars.gamestate='2';et_RunFrame(1900);assert(output.matchId~=first and output.matchComplete==false)
vars.g_gametype='3';vars.g_currentRound='0';vars.gamestate='0';et_RunFrame(2200)
local stopwatch=output.matchId
vars.g_currentRound='1';vars.gamestate='3';et_RunFrame(2500)
assert(output.matchComplete==false,'stopwatch halftime is not match completion')
-- Reloading the VM for the second half keeps the same match identity.
assert(loadfile('luascripts/pappaliiga/pappabroadcast.lua'))();et_InitGame(0,124,1)
vars.gamestate='0';et_RunFrame(100);assert(output.matchId==stopwatch)
vars.g_currentRound='0';vars.gamestate='3';et_RunFrame(400)
assert(output.matchComplete==true,'second half completion uses the playing round')
vars.gamestate='1';et_RunFrame(700);local next_match=output.matchId
assert(next_match~=stopwatch)
vars.gamestate='2';et_RunFrame(1000);vars.gamestate='1';et_RunFrame(1300)
assert(output.matchId==next_match,'cancelled countdown does not split the match')
vars.mapname='radar';et_RunFrame(1600);assert(output.matchId~=next_match,'new map gets a new match')
os.getenv=realgetenv
print('pappabroadcast: all checks passed')
