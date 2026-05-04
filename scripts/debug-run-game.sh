#!/usr/bin/env bash
set -euo pipefail

GAME_DIR="${YOMI_GAME_DIR:-$HOME/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE}"
PROJECT_DIR="${YOMI_PROJECT_DIR:-$HOME/Game-Mods/yomi-hustle/game-decompiled/hustle}"
LOG_DIR="${YOMI_DEBUG_LOG_DIR:-$PWD/debug-logs}"
RUNNER="${GAME_DIR}/YourOnlyMoveIsHUSTLE.x86_64"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/yomi-debug-${STAMP}.log"

mkdir -p "$LOG_DIR"

if [[ ! -x "$RUNNER" ]]; then
	printf 'Missing game executable: %s\n' "$RUNNER" >&2
	exit 1
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
	printf 'Missing project directory: %s\n' "$PROJECT_DIR" >&2
	exit 1
fi

printf 'Writing debug log to %s\n' "$LOG_FILE"
printf 'Warning: AI search logging is very noisy and can make this file large.\n'

export LD_LIBRARY_PATH="${GAME_DIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [[ "${1:-}" == "--print-command" ]]; then
	printf 'LD_LIBRARY_PATH=%q %q --path %q --verbose\n' "$LD_LIBRARY_PATH" "$RUNNER" "$PROJECT_DIR"
	exit 0
fi

if [[ "${1:-}" == "--gdb" ]]; then
	shift
	gdb --args "$RUNNER" --path "$PROJECT_DIR" --verbose "$@"
else
	"$RUNNER" --path "$PROJECT_DIR" --verbose "$@" 2>&1 | tee "$LOG_FILE"
fi
