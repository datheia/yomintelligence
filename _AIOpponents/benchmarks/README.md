# Fast Copy Benchmark

Small timing script for `fast_copy_to`.

Run it with the installed game executable standing in for Godot:

```bash
env LD_LIBRARY_PATH=/home/mert/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE \
  /home/mert/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE/YourOnlyMoveIsHUSTLE.x86_64 \
  --path /home/mert/Game-Mods/yomi-hustle/game-decompiled/hustle \
  --script /home/mert/Game-Mods/yomi-hustle/ai-opponents-fork/_AIOpponents/benchmarks/FastCopyBenchmark.gd \
  --iterations 1000 \
  --warmup 50
```

Install `_AIOpponents` first. The game executable loads installed mods before
the benchmark script, so this measures the installed mod build.

It prints the old `copy_to` path against optimized `fast_copy_to`, then prints
native-helper slices as diagnostics.

Recent local run, 300 iterations / 20 warmup:

- `copy_to` vs `fast_copy_to`: about `50.01x` faster.
- State variables: native helper was about `1.61x` faster.
- State history: GDScript was faster, so the mod keeps that path in GDScript.
- Full GDScript fast-copy vs native-assisted fast-copy: about `1.17x` faster.
- The benchmark now prints a lightweight `accuracy_ok` check against the source
  fighter state plus a few named Ninja state smoke checks. It is still not a
  proof for every move/action state.

The game log gets large quickly while benchmarking. Use low iteration counts
when checking changes, and clear or rotate `user://logs` if you run this a lot.
The missing `SoupModOptions` warning from the installed mod can also repeat and
inflate the log.
