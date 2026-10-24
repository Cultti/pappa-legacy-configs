# Pappaliiga ET: Legacy settings

This repository is the source of truth for deployed server configs and Lua.
See `luascripts/README.md` for module behavior and integration requirements.

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
