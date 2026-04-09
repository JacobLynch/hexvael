# Devlog

## 2026-04-09
- Merged PR #1: multiplayer foundation (step 1 done)
- Headless WebSocket server, 20Hz authoritative tick, delta-compressed snapshots, rate limiting, player cap
- Client-side prediction + server reconciliation + snapshot interpolation for remote players
- Binary protocol for snapshots/inputs, JSON for handshake/join/leave
- Shared arena scene used by both server and client (sync by construction)
- Remote player collision proxies so local prediction can't walk through other players
- Prediction runs at display framerate via `PlayerEntity.move_delta()` for instant input response
- Zombie WebSocket peers disconnected after 10s of silence; `input_seq` widened u16 → u32 (no more 55-min overflow)
- 55+ GUT unit tests covering message encoding, snapshot diffing, input buffering, movement, collision
- Next session: start step 2, movement + combat feel

## 2026-04-08
- Created project, scaffolded folder structure
- Set up EventBus and RNG autoloads (or: not done yet)
- Blocked on: X
- Next session: start step 1, WebSocket foundation