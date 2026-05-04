# YOMI Hustle AI Opponent

Tiny robot brain for **Your Only Move Is HUSTLE**. It picks from moves the live
UI can actually reach, runs a small simulation search, and lets you tune how
hard it reads the opponent.

## What Is In Here

- `_AIOpponents/`: the mod.
- `_AIOpponents/native_src/`: the GDNative fast-copy helper source.
- `_AIOpponents/benchmarks/`: checks for fast-copy speed and snapshot accuracy.
- `CRASH_IDEAS.md`: notes for the crash hunt.
- `DEBUG_RUNNER.md`: a local runner for crash repros and backtraces.

## Notes

- Settings live under `AI Player`, `Depth`, `Reads`, and `Experimental Performance Increase`.
- If no real move is available, it auto-submits `Continue` and still sets `DI`.
- AI vs AI mode is disabled.
- Known bug: some move-action states can still crash during search. The current
  suspect is the GDNative probing / fast-copy path around those states, and it
  needs a real fix before this is release-clean.
- Search debug logging is very loud and can make real game logs huge. Keep
  repro runs short unless you are actively chasing the crash.

## Credits
Thanks to [@AxNoodle](https://github.com/AxNoodle) for providing the base that this mod is built on


## Install

Copy `_AIOpponents` into the game's `mods` directory:

```bash
cp -r ai-opponents-fork/_AIOpponents ~/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE/mods/
```
