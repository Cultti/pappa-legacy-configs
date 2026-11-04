# Stream chat delivery

`luascripts/pappaliiga/pappabroadcast-chat.lua` is canonical here and is appended
to `broadcast-lua-modules.txt`. It sends actual game chat to all clients:
`[Twitch] Viewer: hello` and `[YouTube] Viewer: hello`.

Require **both** `BROADCAST_ENABLED=true` and `BROADCAST_CHAT_ENABLED=true` in
the game environment. Leave the latter unset to disable delivery. Load only on
the live game source, never the private delayed relay. No competition config
automatically opts into chat.

The compatible Auto Broadcast source forwarder polls Stats using its existing
source token and atomically writes a private tmpfs inbox. Set `BROADCAST_CHAT_FILE`
to the same absolute path in game and forwarder. The default is
`BROADCAST_SOURCE_FILE + '.chat'`; set both paths explicitly because collector
and forwarder have different default source filenames. Restrict runtime-directory
write access to the trusted forwarder/game account; never expose a public upload.
The inbox contains data, never console commands. Lua performs no HTTP.

Inbox schema: `{schema:1,session,messages:[{sequence,platform,author,text,sentAt,expiresAt}]}`.
Platform is `twitch` or `youtube`; times are Unix milliseconds, sequence is a
positive safe integer assigned by Stats. Lua reads at most 16 KiB/16 entries
every 500 ms, requires current `pappa_broadcast_session`, rejects expired,
over-30-second-old or over-five-second-future messages, and emits at most one
line every two seconds. Consumed sequence stays in non-archived engine cvars
across Lua reloads, including deliberately dropped spam. Author/text are valid
UTF-8, bounded to 48/220 bytes. Colours, quotes, backslashes, semicolons and
control characters are removed before fixed local labels form a `chat` command.

Delivery is best effort: bursts, file overwrites, restarts and transport failures
can drop messages. There is no durable backlog or acknowledgement. Keep host
clocks synchronized. Stats restart IDs use wall time; after clock rollback,
disable chat before clearing `pappa_chat_session` if cursor recovery is required.
One Stats instance serves one source, matching its existing telemetry model.

Install compatible Stats chat endpoints first, then this canonical Lua and the
matching Auto Broadcast forwarder/worker. Enable `BROADCAST_CHAT_ENABLED=true`
on worker, forwarder and game only after all are ready. No deployment is performed
by this change. Disable the toggle for rollback; retain prior images/settings
and drain active media before restarts.

Run `lua tests/pappabroadcast_chat_test.lua` with Lua 5.4 and dkjson. Coverage
includes labels, hostile commands, UTF-8 bounds, duplicates/reloads, spam,
wrong sessions, stale/future messages, malformed input and opt-in gates.


Once compatible support is installed, runtime control lives in `/admin/broadcast`:
use **Relay Twitch and YouTube chat to the game server**, then **Apply chat relay**.
It defaults off and changes during an active stream without restarting the game
or video outputs. Stats discards queued chat when disabled. The environment opt-ins
above install the capability once; they are not the day-to-day operator switch.
