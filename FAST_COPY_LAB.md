# Fast Copy Lab

This is the scratchpad for making `fast_copy_to` much faster without hand-copying
zips every run.

```bash
scripts/fast-copy-lab.sh build-native
scripts/fast-copy-lab.sh bench --iterations 300 --warmup 20
```

The lab uses the real game executable as `godot`, stages this checkout as
`_AIOpponents.zip`, copies SoupModOptions beside it, and writes logs under
`fast-copy-lab/logs/`.

Useful commands:

```bash
scripts/fast-copy-lab.sh paths
scripts/fast-copy-lab.sh stage
scripts/fast-copy-lab.sh game
scripts/fast-copy-lab.sh restore
```

Logs can get huge because the real search prints a lot. Benchmark with small
iteration counts first, then go bigger only when a change looks promising.
