-- Game source only. The authenticated forwarder atomically writes this private tmpfs inbox.
local ok,json=pcall(require,'dkjson')
local enabled,next_poll,next_send=false,0,0
local path=os.getenv('BROADCAST_CHAT_FILE') or ((os.getenv('BROADCAST_SOURCE_FILE') or '/runtime/source-local.json')..'.chat')
local function integer(n) return type(n)=='number' and n==n and n%1==0 and n>=0 and n<=9007199254740991 end
local function clean(text,limit)
    if type(text)~='string' then return '' end
    -- Remove ET colour/format escapes and all command delimiters; preserve valid UTF-8.
    text=text:gsub('%^.', ''):gsub('[%z\1-\31\127"\\;]', ' '):gsub('%s+',' ')
    local good,length=pcall(utf8.len,text)
    if not good or not length then return '' end
    if #text>limit then
        local cut=limit+1
        while cut>1 and text:byte(cut)>=128 and text:byte(cut)<192 do cut=cut-1 end
        text=text:sub(1,cut-1)
    end
    return text:match('^%s*(.-)%s*$')
end
function et_InitGame()
    enabled=ok and os.getenv('BROADCAST_ENABLED')=='true' and os.getenv('BROADCAST_CHAT_ENABLED')=='true'
    next_poll,next_send=0,0
    if enabled then et.RegisterModname('PappaBroadcastChat 0.1.0') end
end
function et_RunFrame(levelTime)
    if not enabled or levelTime<next_poll then return end
    next_poll=levelTime+500
    local f=io.open(path,'rb');if not f then return end
    local raw=f:read(16385);f:close();if not raw or #raw>16384 then return end
    local success,body,_,err=pcall(json.decode,raw)
    if not success or err or type(body)~='table' or body.schema~=1 then return end
    local session=et.trap_Cvar_Get('pappa_broadcast_session') or ''
    if session=='' or body.session~=session or type(body.messages)~='table' or #body.messages>16 then return end
    local cursor_session=et.trap_Cvar_Get('pappa_chat_session') or ''
    local cursor=cursor_session==session and (tonumber(et.trap_Cvar_Get('pappa_chat_sequence')) or 0) or 0
    local now=os.time()*1000
    for _,line in ipairs(body.messages) do
        if type(line)=='table' and integer(line.sequence) and line.sequence>cursor then
            -- Persist consumed IDs across Lua reloads/maps; dropped spam is never replayed.
            cursor=line.sequence
            et.trap_Cvar_Set('pappa_chat_session',session)
            et.trap_Cvar_Set('pappa_chat_sequence',tostring(cursor))
            local platform=({twitch='Twitch',youtube='YouTube'})[line.platform]
            if platform and integer(line.sentAt) and integer(line.expiresAt) and line.sentAt>=now-30000
                and line.sentAt<=now+5000 and line.expiresAt>=now and line.expiresAt<=line.sentAt+30000 then
                local author,text=clean(line.author,48),clean(line.text,220)
                if author~='' and text~='' and levelTime>=next_send then
                    next_send=levelTime+2000
                    et.trap_SendServerCommand(-1,'chat "['..platform..'] '..author..': '..text..'"')
                end
            end
        end
    end
end
