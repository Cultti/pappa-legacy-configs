# Pappaliiga ET: Legacy settings

This repository is the source of truth for deployed server configs and Lua.
See `luascripts/README.md` for module behavior and integration requirements.
See [stream chat delivery](STREAM_CHAT.md) for opt-in Twitch/YouTube game chat.

Competition defaults `legacy1`, `legacy3`, `legacy5` and `legacy6` run at
**40 Hz**. Explicit 50 Hz alternatives are `legacy1_svfps50`,
`legacy3_svfps50`, `legacy5_svfps50` and `legacy6_svfps50`.
The old `_svfps40` names have been replaced by the unsuffixed defaults.
Config contents and Lua lists are retained by the rename; only selection names
change. Practice and trickjump configs retain their existing rates.

Run `python3 tests/config_rates_test.py` for naming/rate regression checks.
The main-branch sync workflow carries changes to `etl-stats-api` while
preserving its Lua module settings. Before deployment, verify that branch has
the same rate/name mapping and all expected modules. Restore the standard
engine separately from configuration changes; new recordings, not old demos,
reflect the effective server and upstream snapshot rates.

## Experimental automatic broadcast source

Broadcasting is opt-in: set `BROADCAST_ENABLED=true`, place `BROADCAST_SOURCE_FILE`
on local tmpfs, and select the committed `broadcast-lua-modules.txt` with
`+set g_luaModuleList broadcast-lua-modules.txt`. It preserves the normal Stats,
cup and highlights module order and appends the broadcast collector. Deploy the
entire frozen settings tree; the Stats objective IPC sender and collector must
come from the same revision. Disabled collectors do not publish telemetry.

The collector exports bounded roster/damage/kill/objective snapshots without GUIDs.
Its engine-persistent match identity survives Lua reloads and stopwatch halftime;
final intermission marks completion on the same snapshot timeline. A separate
forwarder handles authenticated transport, keeping HTTP outside game frames.
`pappabroadcast-tv.lua` belongs only on the private delayed relay and validates
camera commands before changing and confirming the actual spectator POV.

Run all `tests/*_test.lua` with Lua 5.4 and dkjson before deployment. Keep relay
access private, use an immutable reviewed artifact, and restart an opted-in game
source only after its active match/recorder work has drained. The pilot camera,
director and lifecycle service live in private `Cultti/ETLegacyAutoBroadcast`.
