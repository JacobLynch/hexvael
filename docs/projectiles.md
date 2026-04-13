n action games like path of exile and diablo 3 or 4 how do they handle projectiles in terms of network architecture, client prediction, interpolation, extrapolation, etc... whats the architecture?

8:54 PM

Verified diagram completion and prepared comprehensive technical explanation
Verified diagram completion and prepared comprehensive technical explanation
Great question — this is a surprisingly deep topic with several distinct layers all working together. Let me diagram the architecture first, then walk through each concept.



Both PoE and Diablo use a server-authoritative model — the server is the single source of truth, and clients are essentially trusted-but-verified predictors. Here's how it all fits together:

The server tick loop

The server runs at a fixed tick rate — PoE historically used ~33ms ticks (30Hz), Diablo 4 is similar. Every tick it processes all queued inputs, advances the authoritative simulation, and broadcasts a delta snapshot to all clients. This is the heartbeat everything else is synchronized to.

Client-side prediction

When you click to fire a fireball, your client doesn't wait for a server round-trip. It immediately spawns a local projectile and starts simulating it. Your input is sent to the server with a timestamp (or sequence number), but locally the game has already played the full animation and started flying the bolt. This is why these games feel responsive even on 80ms ping.

The key insight is that your own character's projectiles are cosmetically ahead of the server. They're a bet that the server will agree.

Dead reckoning / projectile simulation

For projectiles moving on predictable paths (straight lines, simple arcs), the client just extrapolates from initial state — origin + velocity + timestamp — rather than receiving position updates every tick. The server does the same simulation with the same seed. As long as both sides agree on the initial conditions, they stay in sync without bandwidth overhead. PoE with 500 chaining projectiles on screen would be unworkable otherwise.

Lag compensation (the clever part)

Here's where it gets interesting for hit detection. When your "fire" input arrives at the server, 60ms has passed. All the monsters have moved since you pulled the trigger. If the server naively checked hit detection against current monster positions, it would miss shots that clearly should have hit from your perspective.

So the server maintains a position history ring buffer — typically ~200–500ms of past entity positions. When it processes your fire input, it rewinds time to when you actually fired (your timestamp minus your network latency), reconstructs where everything was at that moment, and runs hit detection against that snapshot. Then it fast-forwards back to now to apply the damage.

This is why you can hit a monster in PoE that visually walked away from your shot half a second ago — the server honored where it was when you perceived it.

Interpolation vs. extrapolation

For rendering other entities (enemies, other players), the client doesn't predict — it interpolates. It holds a small buffer of the last 2–3 server snapshots (~66–100ms of history) and renders entities at a position between two known snapshots. This is smooth and never wrong, but it means you're watching everything else slightly in the past.

Extrapolation (continuing the last known trajectory when packets are late) is used as a fallback but is dangerous — a fast-moving enemy on a curve will visually teleport when the next snapshot arrives. Most ARPGs prefer interpolation and accept a slightly stale view over the visual pop of extrapolation errors.

Reconciliation

If the server disagrees with your client prediction — say a hit you registered locally gets rejected, or a projectile spawned in a slightly different position due to a latency-caused race — the server's version wins. The client either snaps immediately (jarring but rare) or lerps/rubber-bands over 2–3 frames (smooth, common). PoE actually generates the visual projectile effects locally and doesn't heavily rubber-band them because the cosmetic divergence is usually imperceptible and correcting it looks worse than leaving it.

PoE vs. Diablo 3 vs. Diablo 4 differences

Diablo 3 was infamously peer-to-peer — one player's machine acted as host, which is why the host dying ended the session and introduced host-advantage asymmetries. Diablo 4 moved to dedicated servers. PoE has always been dedicated server. Both D4 and PoE keep hit validation and damage numbers strictly server-side, which is why you sometimes see the visual projectile hit but the damage number appears a frame or two later — that's the server round-trip confirming the kill.

For the absolutely bonkers builds in PoE (Tornado Shot with 500+ projectiles, Archmage Stormcall with hundreds of pending strikes), the engine essentially gives up on sending individual projectile state and instead syncs the seed state — the client reconstructs the full chaos deterministically from the same initial conditions the server used.

So it sounds like clients simulate everything they do locally and just correct from server if they have to. Two things: you talk about hit detection like it’s instant but there are a lot of projectiles that take time to arrive somewhere. How does that work? And 2 tell me more about how they make remote clients shooting projectiles look good. Does the local client simulate remote projectiles too ?

9:22 PM

Deliberated file creation method for SVG rendering
Deliberated file creation method for SVG rendering
These are the two most interesting nuances in ARPG netcode. Let me address them in order — the first one with a diagram because the timing relationship is the key insight.

For travel-time projectiles, lag compensation only fires once — at the moment you shoot.


Clarified lag compensation mechanics and prepared remote projectile explanation
Clarified lag compensation mechanics and prepared remote projectile explanation
S

Show widget
The key insight here: lag compensation only fires once — at the moment the server validates your shot. After that, the projectile exists as a real server entity traveling through server time. No rewinding needed for the hit, because it happened genuinely in the present.

Specifically, when the server receives your fire input:

It looks up your client's RTT (from a rolling average of recent packets)
It fetches the position snapshot from its history buffer at (now - RTT/2)
It validates that your projectile trajectory was legal against that snapshot — did you actually have line of sight? Was the enemy there?
If valid, it spawns an authoritative projectile entity at the rewound position and fast-forwards it to the current tick
From there, the projectile just ticks forward every server frame like any other entity. When it spatially intersects a hitbox, that's a real hit in real time, and the damage fires normally.

This is why in PoE you sometimes see your arrow visually connect but no damage number appears — the client's local sim said "hit" but the server's authoritative trajectory disagreed, possibly because of a tiny initial angle difference or a desynced enemy position.

On rendering remote projectiles — yes, clients simulate them too

This is the "spawn and simulate" pattern, and it's exactly what you'd guess: when another player or enemy fires, the server broadcasts a spawn event containing { type, origin, direction, velocity, timestamp, seed }. Your local client receives this and spins up its own deterministic simulation of that projectile, running the same physics code the server runs.

The timing wrinkle: by the time that spawn event reaches you, the projectile has already been traveling for RTT/2 milliseconds. So the client fast-forwards the local simulation on spawn — it doesn't start from the origin, it starts from origin + velocity * RTT/2. This is why remote projectiles seem to "pop in" slightly ahead of where they were actually spawned; you're catching up to present time.

After that initial catch-up, the client simulates it deterministically frame by frame. For simple straight-line projectiles (most arrows, bolts, basic attacks), the simulation stays in sync indefinitely without any further server updates — the physics is deterministic enough that both sides agree.

For complex paths — projectiles with gravity, PoE skills that chain and fork, homing projectiles — the server periodically broadcasts correction snapshots, and the client lerps to the corrected position. You rarely notice this because the corrections are small and the lerp is fast.

The PoE 500-projectile problem is solved entirely by this pattern. A Tornado Shot returning 500 projectiles doesn't flood the network with 500 position-update streams per tick. The server sends one spawn event per projectile with the deterministic seed, and every connected client runs the full simulation independently. The server only ever sends corrections if a projectile's path diverges meaningfully from what it spawned with — which for most projectiles, never happens.


Projectile timeline
Image · SVG
Makes sense. Can you break this tech down into implementation phases that I can apply to my own game piece by piece

9:33 PM

Architected incremental networking phases tailored for Godot multiplayer games
Architected incremental networking phases tailored for Godot multiplayer games
Six phases. A few things worth calling out that are specific to your situation:

Phase 2 is the one people skip and regret. Input sequencing looks like busywork until you're trying to implement Phase 3 reconciliation and you have no history buffer to replay from. Do it right after Phase 1 while the loop is fresh.

The Godot physics gotcha in Phase 4 is real and will bite you. The moment you let move_and_collide or the PhysicsServer touch a projectile, you've lost determinism across clients. Keep projectile simulation as pure Vector2 math in _physics_process — it's actually simpler code, just manual circle/AABB overlap checks against your tilemap grid.

For a co-op wave defense game, Phase 6 is genuinely optional. The "generous hitboxes" shortcut I mention isn't a hack — it's what shipped ARPGs do. You're not building Valorant; enemies don't sidestep your arrows. The latency artifacts in PvE are mostly imperceptible if your Phase 4 fast-forward is correct and your hitboxes have 20-25% padding.

Web export is the big constraint for phases 1 and 4. WebSocketMultiplayerPeer works fine but you'll need a signaling server or relay if you're doing peer connections. If you're running a dedicated server process (which you should be for authoritative architecture), the WebSocket transport is straightforward — the server runs headlessly and the browser clients connect to it.

# Plan
# Projectile networking — implementation phases

Each phase is playable and shippable on its own. Later phases layer on top without breaking earlier ones.

---

## Phase 1 — Authoritative server loop (foundation)

**What you're building:** The server owns all game state. Clients send input packets; the server processes them each tick and broadcasts a full world snapshot back to all clients. Clients render whatever the server says.

**What it gives you:** Correctness. No cheating, no desync. It will feel laggy (input delay = your RTT/2) but it will always be *right*. Every subsequent phase is about recovering that feeling of responsiveness without sacrificing correctness.

**Key work:**
- Implement a fixed-rate server tick using `_physics_process` (e.g. 20–30 Hz). All game logic runs here, not in `_process`.
- Define an input packet struct: `{ seq: int, tick: int, move_dir: Vector2, actions: int (bitmask) }`. Serialize with `PackedByteArray`.
- Define a snapshot struct: `{ tick: int, last_input_seq: int, entities: Array[EntityState] }`. Delta-compress later; send full state for now.
- For web export, use `WebSocketMultiplayerPeer` on both client and server. ENet won't work in browser.
- Don't simulate anything on the client yet — just display the most recently received snapshot.

**What you're NOT doing yet:** Prediction, interpolation, lag compensation. The game feels like a 200ms input delay. That's expected and fine here.

---

## Phase 2 — Input sequencing and bookkeeping

**What you're building:** Instrumenting the input pipeline so prediction (Phase 3) is possible. This phase has no visible effect on gameplay, but skipping it makes Phase 3 extremely painful to retrofit.

**Key work:**
- Each client maintains a monotonically incrementing `input_seq` counter. Every input packet gets stamped with it.
- Each client maintains an **input history ring buffer** (circular array, ~128 entries). Every input frame, push `{ seq, input_data, client_timestamp }`.
- The server echoes `last_processed_seq` in every snapshot it sends back.
- The client reads this echo and knows: "the server has processed everything up to seq N, so inputs N+1 onward are unconfirmed."
- Add RTT tracking: client stamps outgoing packets with `send_time`, server echoes it back, client computes `rtt = Time.get_ticks_msec() - echoed_send_time`. Keep a rolling average over ~8 samples.

**What you're NOT doing yet:** Using any of this to predict or replay. Just collecting the data.

---

## Phase 3 — Client-side prediction for your own character

**What you're building:** Run a local simulation of your own player's movement and state immediately on input, without waiting for the server. When the server snapshot arrives, reconcile.

**Key work:**
- Maintain a **predicted state** for the local player, separate from the server-authoritative state.
- On every input frame: apply input to predicted state immediately, render from predicted state, then send input to server.
- On snapshot arrival: extract the server's authoritative position for your player. Replay all unconfirmed inputs (from the input history buffer, seq = `last_processed_seq + 1` onward) on top of that authoritative state to get your reconciled prediction.
- **Snap vs. lerp decision:** if `|predicted_pos - reconciled_pos| > threshold` (e.g. 64px / ~1 tile), snap. Otherwise lerp over 3–5 frames. Snapping looks bad during normal play; lerping masks small corrections invisibly.

**Godot note:** Your local movement logic now runs in two places — the prediction path (client, every frame) and the authoritative path (server, every tick). Extract it into a pure function `apply_input(state: PlayerState, input: InputData, delta: float) -> PlayerState` with no side effects. Both paths call the same function. This is the only way to keep them in sync.

**What you're NOT doing yet:** Predicting other players, predicting projectiles, or any hit detection.

---

## Phase 4 — Projectile spawn-and-simulate

**What you're building:** Projectiles that feel instant to fire and smooth to watch, on both your own shots and everyone else's.

### Your own projectiles
Extend Phase 3 prediction to include projectiles. When you fire, spawn a **local cosmetic projectile** immediately and start simulating it. The server also spawns its authoritative version. When the server confirms the spawn (or denies it), reconcile: if positions differ slightly, lerp the visual. If the server denies the spawn entirely (illegal fire), despawn. In practice the client and server agree nearly 100% of the time.

### Remote projectiles (other players + enemies)
This is the bigger piece. The server broadcasts a **spawn event** — not continuous position updates — when any non-local entity fires: `{ id, type, origin: Vector2, direction: Vector2, speed: float, timestamp: int, seed: int }`.

On receipt, the client:
1. Computes transit time: `transit_ms = Time.get_ticks_msec() - timestamp`
2. Calculates the fast-forward offset: `offset = direction * speed * (transit_ms / 1000.0)`
3. Spawns the projectile at `origin + offset` and begins simulating forward from there

This is how PoE handles 500 chaining arrows — one spawn packet per projectile, every client simulates independently.

**Critical Godot gotcha:** Do not use Godot's PhysicsServer or `move_and_collide` for projectile movement if you need deterministic cross-client simulation. Godot's physics is not bit-identical across machines. Instead, implement projectile movement as pure `Vector2` math in `_physics_process`:

```gdscript
position += velocity * delta  # deterministic
# Collision: manual AABB or circle overlap checks against a static tilemap
```

For complex homing or forking projectiles (PoE-style), include the `seed` in the spawn event so all clients generate the same fork pattern from the same RNG seed.

**What you're NOT doing yet:** Lag-compensated hit validation (that's Phase 6). For now, the server validates hits against current entity positions.

---

## Phase 5 — Interpolation for remote entities

**What you're building:** Smooth movement for enemies and other players on your screen, regardless of network jitter.

The problem: even at 20 ticks/sec, entities jump 50ms worth of movement per update. At 60fps your renderer fires 3× between server ticks — without interpolation, remote entities stutter.

**Key work:**
- For each remote entity, maintain a **snapshot buffer**: a small ring of the last 3 received states with their server timestamps.
- Render remote entities at `render_time = now - buffer_delay`, where `buffer_delay` is typically 1.5–2 tick intervals (~75–100ms at 20Hz). This keeps you always between two known snapshots.
- Linearly interpolate position (and angle) between the two bracketing snapshots.

```gdscript
var t = (render_time - snap_a.timestamp) / (snap_b.timestamp - snap_a.timestamp)
visual_position = snap_a.position.lerp(snap_b.position, t)
```

- If the buffer runs dry (packet loss), extrapolate using last known velocity for up to ~200ms, then freeze. Extrapolating longer than ~200ms produces visible pops when the next packet arrives.

**Important:** Do NOT interpolate your own character. It's already predicted ahead. Interpolating it would add visual lag back.

**What you're NOT doing yet:** True lag compensation for hit detection. You're still validating hits against current server positions.

---

## Phase 6 — Lag compensation for hit detection

**What you're building:** The server rewinds entity positions to the moment you fired, so that what you see when you aim is what gets validated when your shot arrives.

This is the most complex phase and the most optional for a co-op game. In PvE wave defense, enemies don't dodge skill shots; small position mismatches are tolerable. Consider shipping without this and adding it only if playtesting surfaces the "I clearly hit that" frustration.

**Key work:**

On the server, maintain a **position history ring buffer** per entity:
```gdscript
const HISTORY_MS = 500
var position_history: Array[{ timestamp: int, position: Vector2 }] = []

func record_position():
    position_history.push_back({ timestamp: Time.get_ticks_msec(), position: global_position })
    # Prune entries older than HISTORY_MS
    while position_history.size() > 0 and \
          Time.get_ticks_msec() - position_history[0].timestamp > HISTORY_MS:
        position_history.pop_front()
```

When processing a fire input from a client, validate the hit like this:
```gdscript
func validate_hit(shooter_rtt_ms: int, projectile_origin: Vector2, target: Entity) -> bool:
    var fire_time = Time.get_ticks_msec() - shooter_rtt_ms / 2
    var rewound_pos = get_position_at(target, fire_time)  # interpolate history buffer
    return circle_overlap(projectile_origin, HIT_RADIUS, rewound_pos, target.hitbox_radius)
```

**Practical shortcut for co-op:** Instead of full position-history rewind, use **generous hitboxes** — server-side hitboxes 15–25% larger than the visual hitbox. Combined with Phase 4's fast-forwarded projectile spawning, this masks most latency-caused misses without the complexity of maintaining per-entity history buffers. This is what many co-op ARPGs quietly do.

---

## Recommended rollout order

| Phase | Milestone | Visible effect |
|-------|-----------|----------------|
| 1 | Basic multiplayer running | Correct but laggy |
| 2 | Input bookkeeping | No visible change |
| 3 | Character prediction | Input latency gone for local player |
| 4 | Projectile simulation | Shots feel snappy, remote projectiles smooth |
| 5 | Entity interpolation | Enemies and allies move smoothly |
| 6 | Lag compensation | "I clearly hit that" bugs fixed |

If you're building web export co-op, phases 1–5 will get you to a game that feels responsive and looks smooth. Phase 6 is polish for PvP or precision-critical PvE.