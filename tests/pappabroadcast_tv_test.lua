local json=require('dkjson')
local command,output,sets={},nil,0
local viewer={['pers.connected']=2,['pers.netname']='BroadcastCamera',['sess.spectatorState']=0,['sess.spectatorClient']=0}
local health=100
os.getenv=function(k)if k=='BROADCAST_ENABLED' then return 'true' end end
io.open=function(path,mode)
    if mode=='r' then return{read=function()return json.encode(command)end,close=function()end} end
    return{write=function(_,body)output=json.decode(body)end,close=function()end}
end
os.rename=function()return true end
et={CS_PLAYERS=100,CS_SERVERINFO=0,RegisterModname=function()end,
trap_Cvar_Get=function()return '1'end,
trap_GetConfigstring=function(index)return index==0 and 'session' or tostring(index-100) end,
Info_ValueForKey=function(text,key)if key=='pappa_broadcast_session' then return 'test-1' end;if text=='5' then return key=='n' and 'Bot5' or '1' end;return ''end,
level_get=function(key)return key=='rawmapname' and 'oasis' or 0 end,
ps_get=function(slot,field,index)if slot~=5 then error('invalid slot')end;if field=='ps.stats' then return health end;return 0 end,
gclient_get=function(slot,field)return viewer[field]end,
gclient_set=function(slot,field,value)viewer[field]=value;sets=sets+1 end}
assert(loadfile('luascripts/pappaliiga/pappabroadcast-tv.lua'))()
et_InitGame(0,1,0)
command={id=1,session='test-1',slot=5,name='Bot5',team=1,cutTimeMs=1000,expiresMs=2000}
et_RunFrame(900);assert(sets==0,'never cut early')
et_RunFrame(1000);assert(viewer['sess.spectatorClient']==5 and viewer['sess.spectatorState']==2)
assert(output.appliedId==1 and output.followedSlot==5)
et_RunFrame(1100);assert(sets==2,'duplicate command is not reapplied')
command={id=2,session='old-session',slot=5,name='Bot5',team=1,cutTimeMs=1000,expiresMs=2000}
et_RunFrame(1200);assert(sets==2 and output.rejected=='invalid_or_session')
command={id=3,session='test-1',slot=5,name='Bot5',team=1,cutTimeMs=1000,expiresMs=2000}
health=0;et_RunFrame(1300);assert(sets==2 and output.rejected=='target_unavailable')
health=100;command.id=4;command.expiresMs=1400;et_RunFrame(1500)
assert(output.rejected=='expired' and sets==2)
print('pappabroadcast-tv: all checks passed')
