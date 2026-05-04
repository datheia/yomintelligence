# Debug Runner

Use this when the AI crashes while enumerating move-action states and you need a
cleaner run than launching through Steam.

```bash
./scripts/debug-run-game.sh
```

Check the resolved command without launching:

```bash
./scripts/debug-run-game.sh --print-command
```

For a native backtrace after a hard crash:

```bash
./scripts/debug-run-game.sh --gdb
```

Then inside `gdb`:

```text
run
bt
```

The script uses the installed Linux game executable as the Godot runner and
opens the decompiled project. Before launch, it creates a local
`debug-game-install/` directory with a copied game executable and its own `mods/`
folder. That matters because the modloader reads mods from the executable's
directory, not from `--path`. Override paths if your layout changes:

```bash
YOMI_GAME_DIR=/path/to/YourOnlyMoveIsHUSTLE \
YOMI_PROJECT_DIR=/path/to/game-decompiled/hustle \
YOMI_SOUP_ZIP=/path/to/SoupModOptions_v1.2.zip \
YOMI_DEBUG_GAME_DIR=/tmp/yomi-debug-game \
./scripts/debug-run-game.sh
```

## Log Warning

The real AI search logs are extremely noisy. They print each searched action,
temporary UI scene, and generated data shape, so normal gameplay can produce a
large log very quickly. Keep repro runs short, capture only the crash window,
and delete old files in `debug-logs/` when they stop being useful.
