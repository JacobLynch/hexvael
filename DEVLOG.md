# Devlog

## 2026-04-09 (movement-feel T2)
- Introduced `PlayerEntity.advance(dt)` as the single canonical movement step shared by client and server
- Replaced framerate-dependent `velocity *= 0.9`-style code with dt-independent math: exponential friction (`exp(-friction*dt)`) and midpoint position integration during accel ramp
- `MovementSystem.tick_all()` renamed to `advance_all(dt)`; server and client reconciliation both call the same function
- Added dt-independence canary test: one coarse step vs ten fine steps must converge to within 0.5px — guards against future regression to framerate-dependent math
- All 74 GUT tests passing

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