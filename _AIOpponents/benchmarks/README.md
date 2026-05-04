# Fast Copy Benchmark

Small timing script for `fast_copy_to`.

Run it with the installed game executable standing in for Godot:

```bash
env LD_LIBRARY_PATH=/home/mert/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE \
  /home/mert/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE/YourOnlyMoveIsHUSTLE.x86_64 \
  --main-pack /home/mert/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE/YourOnlyMoveIsHUSTLE.pck \
  --script /home/mert/Game-Mods/yomi-hustle/ai-opponents-fork/_AIOpponents/benchmarks/FastCopyBenchmark.gd \
  --iterations 1000 \
  --warmup 50
```

Install `_AIOpponents` first so `res://_AIOpponents/native/AIFastCopy.gdns`
resolves during the native pass.

It prints GDScript copy time, native copy time, and the speedup.
