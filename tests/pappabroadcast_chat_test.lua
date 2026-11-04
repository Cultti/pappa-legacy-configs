local json=require('dkjson')
local env={BROADCAST_ENABLED='true',BROADCAST_CHAT_ENABLED='true'}
local cvars={pappa_broadcast_session='live'}
local inbox,commands={},{}
os.getenv=function(k)return env[k]end
os.time=function()return 1000 end
io.open=function()return{read=function()return type(inbox)=='string' and inbox or json.encode(inbox)end,close=function()end}end
et={RegisterModname=function()end,trap_Cvar_Get=function(k)return cvars[k]or''end,
trap_Cvar_Set=function(k,v)cvars[k]=v end,
trap_SendServerCommand=function(slot,cmd)assert(slot==-1);commands[#commands+1]=cmd end}
local function reload()assert(loadfile('luascripts/pappaliiga/pappabroadcast-chat.lua'))();et_InitGame()end
local seq=0
local function line(platform,text)
    seq=seq+1
    return{sequence=seq,platform=platform or'twitch',author='^1Viewer";\\\n',text=text or'Hello!',sentAt=1000000,expiresAt=1030000}
end
local function deliver(t,entry,session)
    inbox={schema=1,session=session or'live',messages={entry}};et_RunFrame(t)
end
reload();deliver(0,line('twitch','Hi";quit\\\n^1red'))
assert(#commands==1 and commands[1]=='chat "[Twitch] Viewer: Hi quit red"',commands[1])
et_RunFrame(500);assert(#commands==1,'same inbox must not replay')
reload();et_RunFrame(0);assert(#commands==1,'reload must retain consumed sequence')
deliver(2000,line('youtube'));assert(commands[2]=='chat "[YouTube] Viewer: Hello!"')
deliver(2500,line());assert(#commands==2,'rate limit drops excess')
et_RunFrame(4500);assert(#commands==2,'dropped spam cannot replay')
deliver(5000,line(), 'old');assert(#commands==2)
local stale=line();stale.sentAt=960000;stale.expiresAt=990000;deliver(5500,stale);assert(#commands==2)
local future=line();future.sentAt=1010000;deliver(6000,future);assert(#commands==2)
deliver(6500,line('discord'));assert(#commands==2)
deliver(7000,line('twitch',string.char(255)));assert(#commands==2,'invalid UTF-8 rejected')
deliver(7500,line('youtube',string.rep('ä',200)));assert(#commands==3 and #commands[3]<310)
assert(utf8.len(commands[3]),'truncation preserves UTF-8')
inbox=string.rep('x',16385);et_RunFrame(8000);assert(#commands==3)
inbox='{bad json';et_RunFrame(8500);assert(#commands==3)
env.BROADCAST_CHAT_ENABLED='false';reload();deliver(9000,line());assert(#commands==3,'opt-in required')
env.BROADCAST_CHAT_ENABLED='true';env.BROADCAST_ENABLED='false';reload();deliver(9500,line());assert(#commands==3)
print('pappabroadcast-chat: all checks passed')
