# Devlog

## 2026-04-12
- Network hardening pass + projectile system refactor on `multiplayer-projectiles` branch, preparing for PR and merge
- Wrote network hardening design spec and implementation plan docs before touching code, then worked through the list
- Input validation and rate limiting: per-player input rate limit (drops excess inputs), `aim_direction` unit-vector validation on decode, log warnings for malformed packets and for ACKs referencing unknown snapshot ticks instead of silent drops
- Memory bounds: `connection_attempts` dictionary bounded so repeat-connect flooding can't grow it unbounded, erase player from server dict *before* `queue_free` to avoid dangling reads, clear stale entries from per-player pending-snapshot buffer on ACK timeout
- Signal lifecycle: `NetServer`, `WorldView`, and `ProjectileView` all disconnect their `EventBus` listeners in `_exit_tree` so scene reloads and quit don't leave dangling connections firing into freed nodes
- Perf: `SnapshotPool` object pooling for snapshot dicts reduces GC pressure under steady tick rate; `NetClient` uses `pop_front` instead of `slice` for pending-input trimming; extracted `TICK_AGE_MAX_MS` constant to one place
- Projectile system refactor (foundation for multiple types, base behavior unchanged): string-keyed `ProjectileTypeRegistry`, movement strategy pattern so types can implement their own `advance` math, type selection passed through `ProjectileSpawnRouter` via context dict, data-driven visual instantiation (visual scene/tint/size sit on the type resource instead of hardcoded in `ProjectileView`)
- Fire latch fix: `KeyboardMouseInputProvider` is `RefCounted` and can't receive Godot input events directly, so it polls via its owner node and sets the latch there; adoption rekey path in `ProjectileView` updated so the view follows the authoritative id after `adopt_authoritative`
- `ProjectileView._process` null guard covers the mid-tick despawn frame ordering edge
- Viewport default size tweak, minor doc updates
- Tests still green: added coverage for signal cleanup regressions, rate limiter, unit-vector validation, snapshot pool round-trips, projectile registry and strategy dispatch
- Not in this PR: damage/health, additional projectile type variants (only the straight-line base is registered), Phase 6 lag compensation against moving targets
- Next session: manual two-browser smoke test, merge, then move to damage/health (step 2 combat half continues)

## 2026-04-11
- Projectile networking phase 4 complete on `multiplayer-projectiles` branch
- Server tick rate bumped 20 → 30 Hz (tighter input latency, smoother remote interpolation, better collision fidelity against fast projectiles)
- `ProjectileEntity` is a pure-data `RefCounted` with canonical `advance(dt, walls, players, enemies)` shared by server tick, client prediction, and client deterministic remote sim — one code path, dt-independent, straight-line motion `position += direction * speed * dt`, manual circle-vs-AABB and circle-vs-circle collision (no Godot physics)
- `DespawnReason` enum lives on `ProjectileEntity`: ALIVE, LIFETIME, WALL, ENEMY, PLAYER, SELF, REJECTED (client-only)
- `ProjectileSystem` owns the per-id dict (MAX_ACTIVE=1024), handles `spawn_authoritative` (monotonic u16 ID), `spawn_predicted` (negative temp id = -input_seq for adoption via input_seq match), `advance` (walls → enemies → players order, rejection timeout for orphan predicted), `adopt_authoritative` (rekeys predicted into authoritative, reconcile lerp under 200px drift, hard snap beyond), `on_despawn_event` (idempotent), per-player cooldown API
- `PlayerPositionHistory` ring buffer (32 samples/player) on the server lets `ProjectileSpawnRouter.handle_fire` rewind the shooter's position to fire time by `round((rtt_ms/2) / TICK_INTERVAL_MS)` ticks, spawn at rewound origin + aim × spawn_offset, fast-forward by RTT/2 so the broadcast origin is the server-now position — this eliminates reconciliation drift for moving shooters entirely
- `NetServer` tracks per-player RTT via `SNAPSHOT_ACK` round-trip timing, rolling average of 8 samples, exposed via `get_rtt_ms(player_id)`
- `NetClient` tracks its own RTT via input-send-time → snapshot ACK (exponential moving average), used by rejection timeout and by `adopt_authoritative` for fast-forward math
- Input packet unchanged size (26 bytes): `dodge_pressed: u8` → `action_flags: u8` bitfield (DODGE=1, FIRE=2). `_fire_latch` on `KeyboardMouseInputProvider` set by left-click, plumbed `consume_fire_press()` → `fire_pressed_latch` → `_send_input` → wire
- New binary messages: `PROJECTILE_SPAWNED` (26 bytes, carries server-now origin post fast-forward) and `PROJECTILE_DESPAWNED` (12 bytes, carries despawn position for view-effect placement). `REJECTED` reason is client-only and filtered out of the broadcast loop by an explicit guard
- `WallGeometry.extract_aabbs(arena_root)` reads 4 wall `Rect2`s from `arena.tscn` at server/client startup — no hardcoded positions, scene is the single source of truth
- `PlayerEntity` and `EnemyEntity` gained cached `get_collision_radius()` for projectile hit detection
- Client-side projectile sim runs with empty player/enemy arrays; enemy/player hit detection is server-authoritative (remote client positions are interpolated and wouldn't agree). Wall collisions are deterministic so every client checks them locally
- `ProjectileView` renders live position from `ProjectileSystem.projectiles` each frame (no interpolation buffer — sim is live), 12-vertex `Polygon2D` circle tinted brighter for local shooter, per-reason despawn particle effects (wall sparks, enemy/player impact flashes, lifetime soft fade)
- `ProjectileSpawnRouter` is the shared fire dispatcher used by both server tick loop and client prediction; same code path constructs authoritative and predicted spawns, just with different context flags
- 217 GUT tests total (68 new this session): CollisionMath primitives, WallGeometry extraction, entity collision radii, ProjectileEntity motion + dt-independence canary + collision branches + reconcile convergence, ProjectileSystem spawn/advance/reject/reconcile/cooldown, PlayerPositionHistory ring buffer, NetServer per-player RTT, ProjectileSpawnRouter both branches, wire encode/decode round-trips, fire round-trip semi-integration test, wall + self-collision end-to-end, two-clients-deterministic-sim convergence, server-rewind validation
- Not in this phase: damage/health/knockback, Phase 6 lag-compensated hit validation against moving targets, projectile-vs-projectile collision, multiple projectile types, spatial grid acceleration, friendly-fire toggle, tunneling fix for speed > radius/tick
- Known deferred: manual two-browser smoke test still pending (automated test suite covers the sim and wire paths; the final visual-feel verification needs to be done by hand)
- Next session: manual smoke test + PR + merge; then move to damage/health (step 2 combat half continues)

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