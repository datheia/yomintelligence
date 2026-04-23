# YOMI Hustle AI Opponent

A stronger AI opponent mod for **Your Only Move Is HUSTLE** focused on:

- visible-UI-legal move selection
- opponent reads without turning into pure Stockfish safety spam
- direct tuning through `Depth` and `Reads`

## Current Behavior

- The AI only chooses moves that are currently visible/reachable through the live action UI.
- If no real move is available, it auto-submits `Continue` and still sets `DI`.
- AI vs AI mode is disabled.

## Settings

- `AI Player`: `Off`, `Player 1`, or `Player 2`
- `Depth`: exact search depth
- `Reads`: how hard the AI leans into opponent prediction
  - `0` = safest
  - `100` = most read-heavy
- `Experimental Performance Increase`: faster ghost-state copying

## Install

Copy the mod folder into the game's `mods` directory:

```bash
cp -r ai-opponents-fork/_AIOpponents ~/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE/mods/
```

If you are packaging it for release, zip the `_AIOpponents` folder itself.

## Notes

- This repo contains source edits for the mod, not a full game build.
- The mod targets local play against the AI.
- The search/eval is intentionally small and simulation-driven rather than full of move-specific hand-authored bias.
