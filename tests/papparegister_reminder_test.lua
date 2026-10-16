-- Run: lua tests/papparegister_reminder_test.lua. No network or shell execution.
local load_module = assert(loadfile("luascripts/pappaliiga/papparegister.lua"))
local now, cvars, clients, files, launches, messages, serial, response, bot
local function setup(keepCvars)
    now = now or 1800000000
    cvars = keepCvars and cvars or {}
    clients, files, launches, messages, serial = {}, {}, {}, {}, 0
    response = { registered = false }
    package.loaded.dkjson = { encode = function() return "payload" end,
        decode = function() return response end }
    os.getenv = function() return "test-key" end
    os.time = function() return now end
    os.tmpname = function() serial = serial + 1; return "/tmp/reminder" .. serial end
    os.execute = function(command) launches[#launches + 1] = command; return true end
    os.remove = function(path) files[path] = nil end
    io.popen = function() error("network pipe would block the game") end
    io.open = function(path, mode)
        if mode == "w" then return {
            write = function(self, value) files[path] = value; return self end,
            close = function() return true end
        } end
        if files[path] == nil then return nil end
        return { read = function() return files[path] end, close = function() end }
    end
    et = {
        trap_Cvar_Get = function(key) return cvars[key] or "" end,
        trap_Cvar_Set = function(key, value) cvars[key] = value end,
        trap_GetUserinfo = function(slot) return clients[slot] or "" end,
        Info_ValueForKey = function(info) return info end,
        gentity_get = function(slot) return clients[slot] and 2 or 0 end,
        trap_SendServerCommand = function(slot, message) messages[#messages + 1] = {slot, message} end,
        RegisterModname = function() end, G_Print = function() end
    }
    load_module()
    et_InitGame(0, 0, 0)
end
local function join(slot, character, isBot)
    clients[slot] = string.rep(character or "A", 32)
    et_ClientConnect(slot, 1, isBot or 0)
    et_ClientBegin(slot)
end
local function tick(seconds)
    now = now + seconds
    et_RunFrame(now * 1000)
end
local function complete(status, exit)
    files["/tmp/reminder1.done"] = exit or "0"
    files["/tmp/reminder1.status"] = status or "200"
    files["/tmp/reminder1.body"] = "json"
    tick(1)
end

-- Delay, detached network call and completion-only notification.
setup(); join(0); tick(9); assert(#launches == 0)
tick(1); assert(#launches == 1 and #messages == 0)
assert(launches[1]:find("--max%-time 5") and launches[1]:find("</dev/null >/dev/null 2>&1 &$"))
tick(1); assert(#messages == 0)
complete(); assert(#messages == 1 and messages[1][1] == 0)
assert(messages[1][2]:find("https://et.aukko.net", 1, true))
-- Map reload and same-GUID reconnect both check again immediately.
setup(true); join(0); tick(10); assert(#launches == 1)
complete(); assert(#messages == 1)
et_ClientDisconnect(0); join(0); tick(10); assert(#launches == 2)
files["/tmp/reminder2.done"] = "0"
files["/tmp/reminder2.status"] = "200"
files["/tmp/reminder2.body"] = "json"
tick(1); assert(#messages == 2)
-- Linked players, invalid responses and HTTP failures remain silent.
setup(); join(0); tick(10); response = {registered = true}; complete(); assert(#messages == 0)
setup(); join(0); tick(10); response = nil; complete(); assert(#messages == 0)
setup(); join(0); tick(10); complete("401"); assert(#messages == 0)
setup(); join(0); tick(10); complete("000", "28"); assert(#messages == 0)
-- Slot reuse, including same-GUID reconnects, cannot receive stale replies.
setup(); join(0); tick(10); et_ClientDisconnect(0); join(0, "B"); complete(); assert(#messages == 0)
setup(); join(0); tick(10); et_ClientDisconnect(0); join(0); complete(); assert(#messages == 0)
-- Bots, invalid GUIDs and disabled reminders do not launch requests.
setup(); join(0, "A", 1); tick(10); assert(#launches == 0)
setup(); join(0, "Z"); tick(10); assert(#launches == 0)
setup(); cvars.pappa_register_reminders = "0"; join(0); tick(10); assert(#launches == 0)
-- Bounded concurrency and timeout without blocking or false reminders.
setup(); for slot = 0, 5 do join(slot, string.char(65 + slot)) end
tick(10); assert(#launches == 4)
tick(11); assert(#messages == 0 and #launches == 6)
print("papparegister reminder tests passed")
