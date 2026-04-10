# Devlog

## 2026-04-10 (session 2)
- Enemy spawning & AI (step 2b, enemy half) on feature/enemy-spawning-ai branch
- EnemyEntity: CharacterBody2D with 4-state machine (SPAWNING→IDLE→CHASING→DEAD), dt-independent steering, sticky aggro with hysteresis
- Steering behaviors: seek toward target, separation via spatial grid (O(n) Dictionary-based hash), exponential turn rate lerp, arrival deceleration near melee range
- Idle wander: enemies drift toward random nearby points when no player in detection_radius, transition to CHASING on detection
- EnemySpawner: configurable timer/batch/max_alive, edge-biased spawn points with minimum distance from players
- SpatialGrid: pure data structure for neighbor lookups, rebuilt each tick, also exposes query_radius for future AoE
- Network: snapshot format extended with 17-byte enemy section (position, state, facing via f16, spawn_timer via f16), backward-compatible; 13-byte binary ENEMY_DIED event
- Client: two-snapshot interpolation for enemies (same as remote players), enemy collision proxies (StaticBody2D on layer 3), player collision mask updated to include enemies
- View layer: EnemyView (sickly green square, facing indicator line, idle wobble, spawn telegraph fade-in, spawn pop tween), death flash effect
- Player collision_mask updated to 5 (layers 1+3) so players body-block enemies and vice versa
- 116 GUT tests total (39 new: spatial grid, enemy entity, steering, aggro, enemy system, spawner, network encoding)
- Next session: merge and start combat feel (frost bolt, damage, health)

## 2026-04-10 (session 1)
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