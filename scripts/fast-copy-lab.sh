#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="${GAME_DIR:-$HOME/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/Game-Mods/yomi-hustle/game-decompiled/hustle}"
SOUP_ZIP="${SOUP_ZIP:-$HOME/.local/share/Steam/steamapps/workshop/content/2212330/2931722541/SoupModOptions_v1.2.zip}"
MODS_DIR="${MODS_DIR:-$GAME_DIR/mods}"
GODOT="${GODOT:-$GAME_DIR/YourOnlyMoveIsHUSTLE.x86_64}"
BENCH_SCRIPT="$ROOT/_AIOpponents/benchmarks/FastCopyBenchmark.gd"
LOG_DIR="$ROOT/fast-copy-lab/logs"
STASH_DIR="$ROOT/fast-copy-lab/stash"

usage() {
	printf '%s\n' \
		"Usage: scripts/fast-copy-lab.sh <command> [args]" \
		"" \
		"Commands:" \
		"  build-native                  Build _AIOpponents/native/libai_fast_copy.so" \
		"  stage                         Zip this checkout into the game install mods folder" \
		"  restore                       Restore files moved aside by the last stage" \
		"  bench [--iterations N] [...]   Stage, then run the fast-copy benchmark" \
		"  game                          Stage, then launch the normal game" \
		"  paths                         Print resolved paths"
}

command="${1:-}"
if [ -n "$command" ]; then
	shift
fi

require_file() {
	if [ ! -e "$1" ]; then
		printf 'Missing required path: %s\n' "$1" >&2
		exit 1
	fi
}

build_native() {
	make -C "$ROOT/_AIOpponents/native_src"
}

stage_mods() {
	require_file "$GODOT"
	require_file "$PROJECT_DIR/project.godot"
	require_file "$SOUP_ZIP"
	mkdir -p "$MODS_DIR" "$STASH_DIR"

	local stamp
	stamp="$(date +%Y%m%d-%H%M%S)"
	local backup="$STASH_DIR/$stamp"
	mkdir -p "$backup"

	for name in _AIOpponents _AIOpponents.zip SoupModOptions_v1.2.zip; do
		if [ -e "$MODS_DIR/$name" ]; then
			mv "$MODS_DIR/$name" "$backup/$name"
		fi
	done

	(
		cd "$ROOT"
		zip -qr "$MODS_DIR/_AIOpponents.zip" _AIOpponents
	)
	cp "$SOUP_ZIP" "$MODS_DIR/SoupModOptions_v1.2.zip"
	ln -sfn "$backup" "$STASH_DIR/latest"

	printf 'Staged current mod zip into: %s\n' "$MODS_DIR"
	printf 'Moved previous files into: %s\n' "$backup"
}

restore_mods() {
	local backup="${1:-$STASH_DIR/latest}"
	if [ ! -e "$backup" ]; then
		printf 'No backup to restore: %s\n' "$backup" >&2
		exit 1
	fi

	rm -f "$MODS_DIR/_AIOpponents.zip" "$MODS_DIR/SoupModOptions_v1.2.zip"
	rm -rf "$MODS_DIR/_AIOpponents"

	for name in _AIOpponents _AIOpponents.zip SoupModOptions_v1.2.zip; do
		if [ -e "$backup/$name" ]; then
			mv "$backup/$name" "$MODS_DIR/$name"
		fi
	done
	printf 'Restored staged mod files from: %s\n' "$backup"
}

run_bench() {
	mkdir -p "$LOG_DIR"
	local stamp log
	stamp="$(date +%Y%m%d-%H%M%S)"
	log="$LOG_DIR/bench-$stamp.log"

	stage_mods
	(
		cd "$GAME_DIR"
		env LD_LIBRARY_PATH="$GAME_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
			"$GODOT" \
			--path "$PROJECT_DIR" \
			--script "$BENCH_SCRIPT" \
			"$@"
	) 2>&1 | tee "$log"
	printf 'Benchmark log: %s\n' "$log"
}

run_game() {
	stage_mods
	(
		cd "$GAME_DIR"
		env LD_LIBRARY_PATH="$GAME_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$GODOT"
	)
}

print_paths() {
	printf 'ROOT=%s\n' "$ROOT"
	printf 'GAME_DIR=%s\n' "$GAME_DIR"
	printf 'PROJECT_DIR=%s\n' "$PROJECT_DIR"
	printf 'SOUP_ZIP=%s\n' "$SOUP_ZIP"
	printf 'MODS_DIR=%s\n' "$MODS_DIR"
	printf 'GODOT=%s\n' "$GODOT"
	printf 'LOG_DIR=%s\n' "$LOG_DIR"
}

case "$command" in
	build-native)
		build_native
		;;
	stage)
		stage_mods
		;;
	restore)
		restore_mods "$@"
		;;
	bench)
		run_bench "$@"
		;;
	game)
		run_game
		;;
	paths)
		print_paths
		;;
	""|-h|--help|help)
		usage
		;;
	*)
		usage >&2
		exit 1
		;;
esac
