# CLAUDE.md — Hexvael
> Permanent rules. Read this every session. Full design detail in ARCHITECTURE.md.

---

## What This Is

2D top-down co-op action game. Dark eldritch tone. Combinatorial magic combat. Shared persistent base building. ARPG gear loop. Browser-playable multiplayer.

---

## Stack

- Godot 4, GDScript
- WebSocket only — never ENet, required for browser export
- Web primary export target, Desktop secondary
- Headless Godot server, hostable anywhere

---

## Hard Rules — Follow In Every File

Update the DEVLOG.md with the appropriate info every time you are about to make a PR.

### Simulation and View are strictly separate

`/simulation` — pure logic, no rendering:
- Never reference visual nodes, shaders, particles, UI, or audio
- All state changes go outward via `EventBus` signals only
- No direct calls into `/view`
- Must run identically headless or with view attached

`/view` — rendering, UI, audio, particles:
- Never mutate simulation state
- Only listen to `EventBus` signals
- Removable without touching simulation code

```
[/simulation] --signals--> [EventBus] --signals--> [/view]
[Input] --commands--> [/simulation]
```

### One RNG instance only

- Singleton: `RNG` autoload in `/autoloads/rng.gd`
- Never call `randf()`, `randi()`, or `RandomNumberGenerator.new()` anywhere else in `/simulation/`
- Always use `RNG.next_float()`, `RNG.next_int()` etc.
- Violating this breaks determinism and server authority

**Exception — `/view/` may use `randf()` for purely visual randomness** (e.g. screen shake jitter, particle scatter). Visual effects are not part of the deterministic simulation and must not drain the shared RNG stream. Never use `RNG.*` in `/view/`; always use the Godot built-in `randf()`/`randi()` there.

### Events carry full context

```gdscript
# WRONG
EventBus.emit_signal("enemy_hit", enemy_id)

# RIGHT
EventBus.emit_signal("enemy_hit", {
    "source_entity": source_id,
    "target_entity": enemy_id,
    "position":      position,
    "element":       element,
    "damage":        damage,
    "tags":          tags,
    "chain_depth":   chain_depth,
    "statuses":      active_statuses
})
```

### TCE triggers are data, not code

```gdscript
# WRONG — hardcoded logic
func on_hit():
    if element == "frost":
        explode("fire")

# RIGHT — data resource
{
    "on":        "enemy_hit",
    "condition": { "element": "frost" },
    "effect":    { "type": "explode", "element": "fire", "radius": "small" }
}
```

New gear and trap behaviors require zero new code — only new trigger data.

### Chain depth on every TCE trigger

Every trigger must check `chain_depth` before firing, increment it when firing, and silently drop events where `chain_depth >= 5`. Without this, interacting procs will infinite loop.

### Headless must always work

Every system must run without a display. If it doesn't, it's in the wrong layer.

### One world scene, used by both server and client

World geometry (collision, terrain, obstacles) lives in a single shared scene (e.g. `shared/world/arena.tscn`) instanced by both `server.tscn` and `client.tscn`. Visuals and collision live together in that scene — the headless server simply never renders the visual nodes.

This guarantees sync by construction. Never define collision or world layout separately per side — if the client is missing collision the server has, prediction diverges and the player rubber-bands.

### Simulation math is dt-independent

Every simulation step function takes a `dt` parameter (seconds since last step) and produces the same result regardless of how dt is chunked. The server calls these functions once per 20Hz tick (`dt = 0.05`); the client may call them every display frame (`dt = frame_delta`) for prediction. They must converge.

```gdscript
# WRONG — framerate-dependent, silently diverges between client and server
velocity *= 0.9                    # depends on how often you call it
dodge_timer -= 1                   # "1 tick" means nothing outside the server loop

# RIGHT — dt-independent, identical results at any call frequency
velocity *= exp(-friction * dt)    # exponential decay
dodge_timer -= dt                  # wall-clock seconds
velocity += accel * dt             # linear accumulation
```

If you can't express a behavior in dt-independent form, it belongs in a layer that runs on a fixed tick (e.g. discrete state transitions), not in the continuous advance path.

### Client and server share simulation code

Prediction on the client and authoritative simulation on the server must call the **same function**, not reimplementations of it. One canonical `advance(dt)` per entity, one canonical system driver. Server calls it at tick rate; client calls it every frame for prediction and again during reconciliation to replay pending inputs. Never fork "client prediction logic" from "server logic" — the moment they diverge, the local player rubber-bands every snapshot.

Rule of thumb: if a movement, combat, or physics behavior appears anywhere on the client, it must be calling the same `/simulation` code the server runs. View code reads state and renders it; it never re-implements simulation.

### View effects must work for both local and remote entities

Simulation events (`player_moved`, `player_collided`, `player_dodge_started`, etc.) only emit on the client that runs the sim. For the local player that's every client (via prediction); for remote players it's only the server — which has no view. View-side effect listeners (particles, trails, screen shake) must therefore work for **all** entities, not just the local player.

For each effect, ask: *"does this event fire for remote players on this client?"* If not, fix it one of three ways in `WorldView._process`:

1. **State diff** — for persistent state (e.g. DODGING). Track previous state per entity; emit synthetic event only on the frame of transition.
2. **Snapshot-driven synthesis** — for continuous values (e.g. velocity → footstep dust). Read the field from the snapshot dict each frame and emit if above threshold.
3. **Counter + auxiliary field in snapshot** — for momentary events (e.g. wall collision). The server increments a u8 counter in the entity snapshot and stores the event's side data (normal, etc.). `WorldView` detects any change in the counter and emits a synthetic event with the side data.

```gdscript
# Pattern 3 — momentary event detection (WorldView._process remote branch)
var collision_count: int = ent.get("collision_count", 0)
var prev_count: int = _prev_remote_collision_count.get(player_id, collision_count)
if collision_count != prev_count:
    EventBus.player_collided.emit({ "entity_id": player_id, ... })
_prev_remote_collision_count[player_id] = collision_count
```

The local player's `PlayerEntity.advance()` emits its own events naturally — don't also synthesize for the local entity (skip the synthesis branch when `player_id == _net_client.get_local_player_id()`).

Counter fields increment even when `_suppress_events` is true (during reconciliation replay) so client and server stay in sync. Never gate the counter increment on `_suppress_events`.

---

## What Not To Build

- No walls — traps only, room geometry funnels enemies
- No crafting chains — no workbench → planks → boots
- No stat-only gear — every effect must be a verb, never just +5 damage
- No player classes — gear creates all divergence, everyone starts identical
- No trap leveling (v1)
- No ENet — WebSocket only

---

## Project Structure

```
/simulation
  /entities     ← entity state, no visuals
  /systems      ← game logic
  /events       ← event definitions
  rng.gd        ← single RNG instance
  event_bus.gd  ← all signals defined here
/view
  /effects      ← particles, shaders, screen effects
  /ui
  /world
/shared
  /triggers     ← TCE definitions as Resources
  /elements     ← element and interaction rules
/autoloads      ← RNG, EventBus
```

---

## Claude Code Behaviour Guidelines

- Avoid ownership-dodging behaviour: if you encounter an issue, take responsibility for it and work towards a solution instead of passing it on to someone else. Don't say things like "not caused by my changes" or say that it's "a pre-existing issue". Instead, acknowledge the problem and take initiative to fix it. Also, don't give up with excuses like "known limitation" and don't mark it for "future work".
- Avoid premature stopping: if you encounter a problem, don't stop at the first obstacle. Instead, keep pushing forward and find a way to overcome it. Don't say things like "good stopping point" or "natural checkpoint". Instead, keep going until you have a complete solution.
- Avoid permission-seeking behaviour: if you have the knowledge and capability to solve a problem, push through. Don't say things like "should I continue?" or "want me to keep going?". Instead, take initiative and act towards the solution.
- Do plan multi-step approaches before acting (plan which files to read and in what order, which tools to use, etc).
- Do recall and apply project-specific conventions from CLAUDE.md files.
- Do catch your own mistakes by applying reasoning loops and self-checks, and fix them before committing or asking for help.

### Use of tools

Adhere to the following guidelines when using tools:

- Always use a **Research-First approach**: Before using any tool, conduct thorough research to understand the context and requirements. This ensures that you use the most appropriate tool for the task at hand. Never use an Edit-First approach. You should prefer making surgical edits to the codebase instead of rewriting whole files or doing large, sweeping changes.
- Use **Reasoning Loops** very frequently. Don't be lazy and skip them. Reasoning loops are essential for ensuring the quality and accuracy of your work.

### Thinking Depth

When working on tasks that require complex problem-solving, always apply the highest **level of thinking depth**.

When thinking is shallow, the model outputs to the cheapest action available. We don't want that. We don't mind consuming more tokens if it means a better output. So always apply the highest level of thinking depth.

Never reason from assumptions, always reason from the actual data. You need to read and understand the actual code, publication or documentation in order to make informed decisions. Don't rely on assumptions or guesses, as they can lead to mistakes and misunderstandings.


## Error Handling Philosophy: Fail Loud, Never Fake

Prefer a visible failure over a silent fallback.

- Never silently swallow errors to keep things "working."
  Surface the error. Don't substitute placeholder data.
- Fallbacks are acceptable only when disclosed. Show a
  banner, log a warning, annotate the output.
- Design for debuggability, not cosmetic stability.

Priority order:
1. Works correctly with real data
2. Falls back visibly — clearly signals degraded mode
3. Fails with a clear error message
4. Silently degrades to look "fine" — never do this

## Build Order

Do not start a step until the previous one is fun to play.

1. Multiplayer foundation — WebSocket, two browsers, character moves and syncs
2. Movement + combat feel — both must feel great, one spell, one enemy, juice hard
3. Unified effect system — TCE + surfaces + element interactions all connected
4. Persistence — serialize/deserialize, server pause/resume
5. Wave spawning — fixed timer, enemies path from stronghold direction
6. One stronghold room — push, clear, capture, hold
7. One POI — enemy camp, aggro, drops, one production building
8. Content expansion
