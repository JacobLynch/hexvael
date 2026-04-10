# Devlog

## 2026-04-10
- Merged PR #2: step 2 movement feel
- Single canonical `PlayerEntity.advance(dt)` shared by client prediction, server authority, and reconciliation replay — midpoint integration for dt-independence
- Dedicated dodge with i-frames, 200ms duration, 700ms cooldown, Hades-pattern direction (input dir or aim fallback), impulse semantics
- Camera rig with deadzone, mouse lookahead, scroll-wheel + macOS trackpad pinch zoom, exponential shake decay
- Six juice listeners: dodge trail (Line2D afterimage), footstep dust, wall bump particles + camera shake, screen shake on local dodge, walk pulse, i-frame tint
- InputProvider abstraction with KeyboardMouseInputProvider; gamepad slots in later as constructor swap
- Network protocol extended: input 17B → 26B (aim_direction, dodge_pressed); snapshot 15B → 45B (velocity, aim_direction, state, dodge_time_remaining, collision_count, last_collision_normal)
- Reconciliation restores full dodge + collision state from server snapshots before replay; events suppressed during replay so view juice never double-fires
- Three new CLAUDE.md hard rules: dt-independent simulation math, shared simulation code, view effects for local and remote entities (three sync patterns documented)
- 100 GUT unit tests including dt-independence canary and reconciliation convergence canary
- Arena scaled 5x (480x320 → 2400x1600) for camera room under new zoom
- Next session: start combat feel (step 2 combat half)

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