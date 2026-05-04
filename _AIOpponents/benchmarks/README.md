# Fast Copy Benchmark

`FastCopyBenchmark.gd` compares two `fast_copy_to` modes on the same live source
game state:

- baseline: the first GDScript fast-copy path, with native C disabled
- improvement: the current C-assisted native fast-copy path, with native C enabled

It checks accuracy by snapshotting the baseline and native-copy targets after one
copy and recursively diffing the snapshots. It checks speed by timing repeated
copies with `OS.get_ticks_usec()`.

## Usage

Run this from a Godot context that already has:

- a live source `Game` with `game_started == true`
- two compatible target `Game` instances initialized for the same match
- `_AIOpponents/native/libai_fast_copy.so` or `ai_fast_copy.dll` installed next
  to the game executable for the native run

The installed Linux game executable can parse-check the benchmark script with:

```bash
env DISPLAY=:0 /home/mert/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE/YourOnlyMoveIsHUSTLE.x86_64 \
  --main-pack /home/mert/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE/YourOnlyMoveIsHUSTLE.pck \
  --check-only \
  --script /home/mert/Game-Mods/yomi-hustle/ai-opponents-fork/_AIOpponents/benchmarks/FastCopyBenchmark.gd
```

Run the benchmark with:

```bash
env DISPLAY=:0 /home/mert/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE/YourOnlyMoveIsHUSTLE.x86_64 \
  --main-pack /home/mert/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE/YourOnlyMoveIsHUSTLE.pck \
  --script /home/mert/Game-Mods/yomi-hustle/ai-opponents-fork/_AIOpponents/benchmarks/FastCopyBenchmarkRunner.gd \
  --iterations 1000 \
  --warmup 100
```

Example:

```gdscript
var bench = preload("res://_AIOpponents/benchmarks/FastCopyBenchmark.gd").new()
add_child(bench)

var result = bench.run(live_game, gdscript_target_game, native_target_game, 250, 25)
if not result["accuracy_ok"]:
	print(result["differences"])
```

The runner prints:

- `baseline_gdscript_usec_per_copy`
- `native_c_usec_per_copy`
- `speedup`
- up to 20 accuracy diffs

## Extending Coverage

Improve the `snapshot_*` helpers as new `fast_copy` behavior is optimized. Add
fields before optimizing them so regressions show up as accuracy diffs.
