-- Run: lua tests/pappahighlights_test.lua
local now, payload, writes = 1000, nil, 0
local vars={sv_maxclients='6',gamestate='2',sv_etltv_password='relay-secret'}
local clients={{connected=2},{connected=2},{connected=2},{connected=2},{connected=2,flags=8},{connected=2,protocol='284',password='relay-secret'}}
package.preload.dkjson=function()return{encode=function(value)payload=value;return 'json' end}end
os.getenv=function(name)if name=='HIGHLIGHT_AUTOMATION_ENABLED' then return 'true' end; if name=='HIGHLIGHT_PRESENCE_FILE' then return '/presence.json' end; return nil end
os.time=function()return now end
io.open=function()return{write=function(self)writes=writes+1;return self end,close=function()return true end}end
os.rename=function()return true end
et={GS_PLAYING=2,RegisterModname=function()end,trap_Milliseconds=function()return 1 end,
 trap_Cvar_Get=function(name)return vars[name] or '' end,trap_Cvar_Set=function(name,value)vars[name]=value end,
 gentity_get=function(slot,field)local c=clients[slot+1] or {};return field=='pers.connected' and c.connected or c.flags or 0 end,
 trap_GetUserinfo=function(slot)return tostring(slot) end,
 Info_ValueForKey=function(info,key)local c=clients[tonumber(info)+1];return key=='protocol' and c.protocol or c.password end}
assert(loadfile('luascripts/pappaliiga/pappahighlights.lua'))()
et_InitGame(0,123,0);et_RunFrame(0)
assert(payload.humans==4,'bot and authenticated relay excluded')
assert(payload.sessionStartedAt==1000,'competitive session timestamp')
assert(payload.password==nil and payload.userinfo==nil,'credentials never persisted')
clients[4].connected=0;now=1100;et_RunFrame(15000)
assert(payload.humans==3 and payload.sessionStartedAt==1000,'human spectators count; session kept while briefly quiet')
now=4700;et_RunFrame(30000);assert(payload.sessionStartedAt==0,'quiet session clears after an hour')
clients[4].connected=2;now=4800;et_RunFrame(45000);assert(payload.sessionStartedAt==4800,'new session starts before last-busy updates')
clients[6].password='wrong';now=4815;et_RunFrame(60000);assert(payload.humans==5,'unauthenticated spectator counts')
print('pappahighlights: all checks passed')
