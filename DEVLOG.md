# Devlog

## 2026-04-09
- Step 2 movement feel complete (movement half — combat is a separate effort)
- PlayerEntity.advance(dt) is the single canonical movement step shared by client prediction and server authority — same code path, no forks
- Two new hard rules in CLAUDE.md: simulation math must be dt-independent, client and server share simulation code
- Light accel/friction baseline (~0.11s to top speed, exponential decay), midpoint integration for dt-independence under linear accel
- Dedicated dodge: Hades-pattern direction (move_input if held, else aim_direction), 200ms duration, 700ms cooldown, full-duration i-frames, hard-set velocity (impulse semantics)
- Network protocol: input message 17B → 26B (+aim_direction, +dodge_pressed), per-entity snapshot 15B → 36B (+velocity, +aim_direction, +state, +dodge_time_remaining), DODGING flag in EntityFlags
- Client-side prediction predicts dodge immediately via edge-triggered latch; reconciliation restores full dodge state from server snapshot
- Remote player interpolation extrapolates past the snapshot window using snapshot velocity for smoother dodges
- Camera rig: deadzone + mouse lookahead + exponential shake decay (uses Godot built-in randf, not the deterministic RNG stream)
- PlayerView visuals: facing indicator (Line2D rotated to aim_direction), i-frame tint, walk pulse
- Juice: dodge trail (Line2D afterimage), footstep dust (CPUParticles2D every 24px), wall bump (particles + camera shake), screen shake on local player dodge — all view-side listeners on EventBus, never mutate sim state
- InputProvider abstraction with KeyboardMouseInputProvider (gamepad slots in later as a constructor swap); edge-triggered dodge latch survives display-rate-to-tick-rate cadence gap
- Simulation events suppressed during reconciliation replay so view-side juice doesn't double-fire
- 98 GUT unit tests, including dt-independence canary and reconciliation convergence canary as regression guards
- Next session: step 2 combat half — frost bolt + one enemy type + hit feedback

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