#!/usr/bin/env bash
set -euo pipefail

GAME_DIR="${YOMI_GAME_DIR:-$HOME/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE}"
PROJECT_DIR="${YOMI_PROJECT_DIR:-$HOME/Game-Mods/yomi-hustle/game-decompiled/hustle}"
LOG_DIR="${YOMI_DEBUG_LOG_DIR:-$PWD/debug-logs}"
MOD_SRC="${YOMI_MOD_SRC:-$PWD/_AIOpponents}"
SOUP_ZIP="${YOMI_SOUP_ZIP:-$HOME/.local/share/Steam/steamapps/workshop/content/2212330/2931722541/SoupModOptions_v1.2.zip}"
DEBUG_GAME_DIR="${YOMI_DEBUG_GAME_DIR:-$PWD/debug-game-install}"
SOURCE_RUNNER="${GAME_DIR}/YourOnlyMoveIsHUSTLE.x86_64"
RUNNER="${DEBUG_GAME_DIR}/YourOnlyMoveIsHUSTLE.x86_64"
MODS_DIR="${DEBUG_GAME_DIR}/mods"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/yomi-debug-${STAMP}.log"

mkdir -p "$LOG_DIR"

if [[ ! -x "$SOURCE_RUNNER" ]]; then
	printf 'Missing game executable: %s\n' "$SOURCE_RUNNER" >&2
	exit 1
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
	printf 'Missing project directory: %s\n' "$PROJECT_DIR" >&2
	exit 1
fi

if [[ ! -d "$MOD_SRC" ]]; then
	printf 'Missing mod source directory: %s\n' "$MOD_SRC" >&2
	exit 1
fi

if [[ ! -f "$SOUP_ZIP" ]]; then
	printf 'Missing SoupModOptions zip: %s\n' "$SOUP_ZIP" >&2
	exit 1
fi

stage_debug_install() {
	rm -rf "$DEBUG_GAME_DIR"
	mkdir -p "$MODS_DIR"
	cp "$SOURCE_RUNNER" "$RUNNER"
	cp "$SOUP_ZIP" "${MODS_DIR}/SoupModOptions_v1.2.zip"
	cp -a "$MOD_SRC" "${MODS_DIR}/_AIOpponents"

	# These are loaded relative to the executable path by the game/runtime.
	for file in libsteam_api.so tbfg.so libai_fast_copy.so steam_appid.txt; do
		if [[ -e "${GAME_DIR}/${file}" ]]; then
			ln -sf "${GAME_DIR}/${file}" "${DEBUG_GAME_DIR}/${file}"
		fi
	done
}

printf 'Writing debug log to %s\n' "$LOG_FILE"
printf 'Warning: AI search logging is very noisy and can make this file large.\n'
printf 'Using mod source: %s\n' "$MOD_SRC"
printf 'Staging debug game dir: %s\n' "$DEBUG_GAME_DIR"

export LD_LIBRARY_PATH="${DEBUG_GAME_DIR}:${GAME_DIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [[ "${1:-}" == "--print-command" ]]; then
	printf 'stage debug executable and mods into %q, then run:\n' "$DEBUG_GAME_DIR"
	printf 'LD_LIBRARY_PATH=%q %q --path %q --verbose\n' "$LD_LIBRARY_PATH" "$RUNNER" "$PROJECT_DIR"
	exit 0
fi

stage_debug_install

if [[ "${1:-}" == "--gdb" ]]; then
	shift
	gdb --args "$RUNNER" --path "$PROJECT_DIR" --verbose "$@"
else
	"$RUNNER" --path "$PROJECT_DIR" --verbose "$@" 2>&1 | tee "$LOG_FILE"
fi
