local json=require('dkjson')
package.preload['luascripts/stats/util/utils']=function()return{}end
local received
os.getenv=function(k)if k=='BROADCAST_ENABLED' then return 'true' end end
et={trap_Cvar_Get=function()return '3'end,FindMod=function()return 'PappaBroadcast 0.1.0'end,
IPCSend=function(vm,message)assert(vm==3);received=json.decode(message)end,trap_Milliseconds=function()return 999999 end}
local gamelog=assert(loadfile('luascripts/stats/gamelog.lua'))()
gamelog.init(true)
gamelog.objective('obj_defused','GUID-ONE','Dynamite')
assert(received.kind=='broadcast_objective' and received.guid=='GUID-ONE' and received.label=='obj_defused')
assert(received.timeMs==nil and received.leveltime==nil,'never forward incompatible Stats timestamps')
received=nil;gamelog.record('kill','player',{player='GUID-ONE'})
assert(received==nil,'do not duplicate combat events')
print('broadcast objectives: all checks passed')
