# Project Architecture Document
> Living document — update this when decisions change. Always give this to Claude Code at the start of a session.

---

## Vision

A 2D top-down co-op action game with ARPG gear progression, combinatorial magic combat, and shared persistent base building. The core fantasy is logging in to see what your friends built while you were gone and wanting to contribute something cool yourself.

**Tone:** Eldritch, arcane, ritualistic, dark. Magic feels ancient and dangerous. The stronghold feels genuinely threatening. The world has weight and mystery.

**Combat feel:** Juicy, chaotic, powerful. Magicka-style accidental friendly fire. Path of Exile-style meaningful gear. Valheim-style shared world ownership.

---

## Technology

- **Engine:** Godot 4
- **Language:** GDScript
- **Multiplayer:** WebSocket (required for browser export)
- **Export targets:** Web (primary), Desktop (secondary)
- **Server:** Headless Godot process, hostable anywhere (cloud VPS, player machine, etc). Managed by systemd or equivalent, auto-restarts on crash.
- **Persistence:** Serialize world to disk on last player exit, deserialize on first player join.
- **Player cap:** ~8 players (soft limit, not hard technical limit)

---

## Architecture Principles

These are non-negotiable structural decisions. Claude Code must follow them in every system built.

### 1. Simulation / View Decoupling — CRITICAL

The game is split into two completely separate layers:

**Simulation layer** — pure game logic, no rendering, no UI
- Runs identically headless (server, tests) or with a view attached (client)
- Never references any display, UI, or rendering node directly
- All state changes are communicated outward via **events/signals only**
- No direct method calls from simulation into view

**View layer** — rendering, UI, audio, visual effects
- Listens to the simulation event bus
- Never directly mutates simulation state
- Queries simulation state only through a defined read-only interface if needed
- Could be completely replaced or removed without touching simulation code

```
[Simulation] --events/signals--> [View / UI / Audio]
[Player Input] --commands-------> [Simulation]
```

**Why this matters:**
- The headless server runs the simulation with no view attached at all
- Automated tests drive the simulation directly without rendering
- UI changes never risk breaking game logic
- Multiplayer: server runs simulation only, clients run view synced to server state

### 2. Deterministic Simulation

- One global seeded RNG instance used for **everything** — no scattered `randf()` calls
- Same seed + same input sequence = identical simulation output every time
- RNG singleton initialized at world creation, seed saved with world state
- Critical for server authority, replay, and testing

### 3. Event-Driven Systems

- Game systems communicate via a global event bus (signals in Godot)
- No tight coupling between subsystems
- Systems announce what happened — listeners decide what to do about it
- Example: `CombatSystem` emits `enemy_died(enemy_id, position)` — `LootSystem`, `AudioSystem`, `ParticleSystem` each listen and respond independently

### 4. Headless First

- Every system must work without a SceneTree display
- Test the simulation in headless mode regularly
- If a system can't run headless, it belongs in the view layer

---

## World Structure

Top-down 2D view. The map has a conceptual axis navigated from above:

```
[THE WILDS] <--- [CAMP + CAPTURED ROOMS] ---> [ENEMY STRONGHOLD]
procedural            player-built zone           hand-crafted
POIs + resources      trap gauntlet               escalating rooms
gear drops            production buildings         upgrades/power
```

- **Enemies spawn inside the stronghold** and push outward toward camp
- **The Wilds are behind camp** — procedurally generated with hand-crafted POIs sprinkled in
- **Camp and captured rooms** sit between the two — the player-built zone
- **Attacks come primarily from the stronghold direction**

### Stronghold Visual Identity
Dark stone fortress / castle / dungeon aesthetic. Ancient, foreboding, eldritch undertones. Hand-crafted rooms with deliberate layout. Finite sequence of rooms with escalating difficulty, ending in a final boss. Expansions go deeper.

### Player Character
Robed ritualist. Anonymous, arcane, dark fantasy silhouette. Visual identity reinforces the eldritch tone.

---

## Core Loop

1. Explore The Wilds → find gear components, resources, POIs
2. Bring resources back → build/upgrade production buildings in captured rooms
3. Production buildings generate crafting materials over time
4. Combine components at production buildings → craft gear and traps
5. Push into the stronghold → clear a room (multiple attempts expected)
6. Capture cleared room → more space for production buildings + new upgrades
7. Defend against waves using traps + player combat
8. Maintain traps between waves
9. Repeat — each room opens more space and harder pressure

**Space is always at a premium.** You always want more production buildings than you have room for. Capturing a new room feels great because you can finally place that backlog of buildings — but now you have more to defend.

**Session shapes:**
- Short → defend, quick wilds run, drop off resources
- Long → coordinated stronghold push
- Solo → exploration, crafting, base prep
- Co-op → assault, base redesign, production planning

---

## Waves

- **Fixed timer** between waves
- Timer visible to players — creates planning pressure ("2 minutes, go")
- When timer hits zero, enemies spawn from the stronghold and push toward camp
- Wave difficulty escalates over time and with each room captured
- Players cannot delay or skip waves — the pressure is constant

---

## Spell / Effect Construction System

**The deepest system in the game. Noita meets Magicka.**

### Structure
Every effect (spell, trap trigger, gear proc) is built from:
1. **One base effect** — the element
2. **One or more mods** — applied in sequence, order matters

### v1 Elements
- **Frost** — slows, chills, freezes
- **Fire** — burns over time, ignites, spreads

### v1 Mods
- **Splitter** — divides the effect into 3 weaker versions
- **Focuser** — concentrates into 1 stronger version

### Mod Ordering Matters
```
frost + splitter                        → 3 weak frost bolts
frost + focuser                         → 1 strong frost beam
frost + splitter + focuser              → 3 focused frost beams
frost + focuser + splitter              → 1 beam that splits into 3 on impact
frost + splitter + focuser + splitter   → 3 focused beams each splitting into 3
```

Enormous depth from a small number of primitives. Players discover — they don't follow recipes.

### Combined / Environmental Effects
Elements interact when they meet in the world:
- Frost + Fire → Steam (blinds, obscures vision)
- Interactions emerge from the rule system, not hand-scripted cases

### Environmental Interaction Rules
- **Frost** → slows enemies, freezes water tiles, extinguishes fire
- **Fire** → burns over time, ignites flammable surfaces, melts ice
- **Steam** → blinds enemies, obscures vision

### Element Delivery
Effects can be delivered as projectiles, AOE bursts, lingering zones, beams — whatever the mod configuration produces. Delivery type emerges from mod combination, not a separate system.

### Friendly Fire
Intentional and expected. Part of the dark ritualistic chaos fantasy.

### Unified — Same System Everywhere
| Context | How the effect manifests |
|---|---|
| Player spell | Actively cast |
| Gear (worn) | Triggers on condition (on hit, on kill, on damage taken, etc.) |
| Trap (placed) | Triggers on proximity or environment condition |
| Room capture | Passive environmental aura in that zone |

Learning frost + splitter on your staff immediately teaches you what a frost + splitter trap does.

---

## The Interaction Engine — CORE SYSTEM

**This is the most important system in the game.** Everything interesting — combat feel, emergent gameplay, player expression, build depth — flows from this. It must be designed carefully and built early. Every other system plugs into it.

It has three layers that speak to each other through one shared event bus.

---

### Layer 1: Trigger / Condition / Effect (TCE) System

Every entity in the game (player, enemy, trap, gear piece, room, tile) is a bag of triggers. A trigger is a data structure — not code — that says: **when X happens, if Y is true, do Z.**

```gdscript
# Example trigger on a gear piece
{
  on:        "enemy_hit",
  condition: { element: "frost" },
  effect:    { type: "explode", element: "fire", radius: "small" }
}

# Example trigger on a trap
{
  on:        "enemy_enters_tile",
  condition: {},
  effect:    { type: "apply_status", status: "frost", strength: 1 }
}

# Example trigger on a room capture
{
  on:        "enemy_damaged",
  condition: { chain_depth_lt: 3 },
  effect:    { type: "spread_to_nearest", copy_effect: true }
}
```

**Triggers are data, not code.** Defining new gear, new traps, new room effects requires zero new code — just new trigger definitions. This is what makes the system infinitely extensible.

**Every event carries fat context.** Listeners filter on whatever they care about:

```gdscript
{
  type:          "enemy_hit",
  source_entity: id,
  target_entity: id,
  position:      Vector2,
  element:       "frost",
  damage:        45,
  mods:          ["focuser"],
  tags:          ["projectile", "spell", "player_cast"],
  chain_depth:   2,
  statuses:      ["wet", "slowed"]
}
```

**Chain depth is non-negotiable.** Every trigger checks `chain_depth` before firing and increments it when it does. Max depth of ~5. Events exceeding max depth are silently dropped. Without this, two interacting procs will infinite loop and crash the server.

**Tag exclusions prevent obvious loops:**
```gdscript
{ tags: ["no_chain"] }  # this event will not trigger other on_hit effects
```

**Triggers can fire complete effect constructions, not just raw effects.** A kill trigger can re-fire the player's current weapon configuration as a nova — it doesn't hardcode the element, it references whatever the player currently has equipped. This creates emergent combinations nobody designed.

---

### Layer 2: Surface and Status System

Inspired by Divinity: Original Sin. The world has persistent state that participates in combat.

**Tile surfaces** — persistent effects on the ground:
- Fire surface, frost surface, water, oil, steam cloud
- A surface is just a persistent area trigger: `WHILE entity_on_tile: apply(element, per_tick)`
- Surfaces ARE traps in the TCE system — no separate implementation needed
- Surfaces have tick rates and durations — comprehensible, not frame-rate chaos

**Entity statuses** — conditions on enemies and players:
- Burning, slowed, frozen, wet, shocked, blinded, staggered
- Applied by surfaces, spells, traps, gear procs
- Statuses themselves emit events that trigger TCE chains

**Interaction rules** — element combinations produce new states:
```
wet + electricity  → shocked (+ chain to nearby wet entities)
oil + fire         → burning surface (spreads)
frost + fire       → steam cloud (blinds, persists)
burning + wet      → extinguished + chilled
```

Rules are data, not code. Adding a new interaction is adding a row to a table. The system evaluates rules automatically when statuses/surfaces combine.

**Surfaces as tactical terrain:**
- Frost surface slows all movement across it — friend and foe
- Fire surface damages anyone crossing — friendly fire applies
- Steam cloud blocks line of sight for everyone — use it or be caught in it
- Oil surface accelerates fire spread — place carefully

**Additional layers beyond surfaces and statuses:**

**Momentum / physics layer** — knockback carries velocity. An enemy knocked into a frost surface slides further. Slides into a wall — impact damage, stagger. Physics state is part of event context `{velocity: Vector2, sliding: true}`. Nobody designs "frost + knockback = wall slam" — it emerges.

**Visibility / perception layer** — line of sight as a first-class rule. Enemies can't aggro through walls. Steam breaks LOS rules, which is why it blinds — not a special case, it's the same system. Players can exploit this deliberately.

**Structural layer (later)** — destructible and flammable environment tiles. Fire spreads to wooden tiles. Frost creates ice bridges over water. Enemies can breach weakened walls. Environment becomes a participant in combat.

**Charge / threshold layer** — entities accumulate charges from repeated hits. Three frost hits → frozen solid. Two fire ticks → ignited (stronger burn). Players learn thresholds and build around them.

**Faction layer (later)** — enemies have elemental allegiances. A fire elemental heals from fire surfaces but is vulnerable to frost. Enemy factions can accidentally damage each other. Players exploit this.

---

### Layer 3: Visual Event Queue

**The simulation and the view run at the same pace — not decoupled.**

The simulation resolves chain events at gameplay speed (2-4 frames per step), not CPU speed. Enemies are in a "resolving" state during chains — staggering, reacting, visually participating. Death and final state commit only when the chain completes. Players always see an entity doing something meaningful.

**Two event types:**

**Committed** — simulation state already changed, visual confirms it. Fire and forget. Never blocks. Most effects are this type.

**Gated** — next simulation step shouldn't happen until this one reads clearly. Uses a minimum display duration, then unblocks regardless of animation completion. Use sparingly.

**Parallel tracks with dependencies:**

The visual queue runs multiple lanes simultaneously, syncing only at explicit dependency points:

```
TRACK A (entity):      [stagger 4fr] → [frost applies] → [slow anim] → [death]
TRACK B (environment): [frost surface spreads] → [fire trap winds up] → [steam blooms]
TRACK C (other):       [nearby enemies react] → [scatter]
TRACK D (audio):       [impact] → [freeze crackle] → [fire whomp] → [steam hiss]
                                          ↑
                             SYNC: steam must exist before blind applies
```

Each queued visual event carries:

```gdscript
{
  effect:      "frost_apply",
  duration:    6,           # minimum frames before unblocking this track
  blocking:    false,       # does this gate the next event on this track
  track:       "entity_A",  # which lane it runs on
  depends_on:  [],          # event IDs that must complete first
}
```

**The minimum duration rule:** Never wait for animation completion — animations can be interrupted or scaled. Wait for a minimum perceived duration (4-6 frames), then unblock. The animation finishes naturally in the background as fire-and-forget. Players don't notice.

**Sequential vs parallel — the practical rule:**
- **Sequential** (same track, gated): things happening *to the same entity* in a causal chain. Stagger → frost applies → enemy reacts. Must read as cause/effect.
- **Parallel** (separate tracks): things happening to *different entities* or in the environment simultaneously. Always parallel unless there's a specific visual dependency.
- **Test:** would it look wrong if these happened at the same time? If yes, add a dependency. If no, let them run parallel.

**Hitstop:** 3-6 frame freeze on significant initiating hits only — not on each chain step. The first impact freezes briefly. Then the chain unfolds at paced speed. Sells weight without slowing the game.

**Visual identity per element** (readable at a glance):
- Frost → blue crystals, downward slow particles, cold shimmer
- Fire → orange upward movement, heat distortion, spreading ember particles
- Steam → white outward bloom, obscuring fog, dissipating edges

**The payoff:** All feel tuning lives in the view layer data. Chain feels too fast? Increase minimum durations. Two effects fight for attention? Add a dependency. Disconnected from cause? Make it sequential. Zero simulation code touched.

---

### How the Three Layers Connect

```
PLAYER CASTS frost + focuser
        ↓
TCE: fires frost beam projectile (Layer 1)
        ↓
PROJECTILE hits enemy
        ↓
EVENT: enemy_hit { element: frost, tags: [projectile] }
        ↓
SURFACE SYSTEM: frost surface created at impact point (Layer 2)
STATUS SYSTEM:  frost status applied to enemy
        ↓
TCE: gear trigger fires — ON: enemy_hit IF: frost → explode(fire, small) (Layer 1)
        ↓
EVENT: explosion { element: fire, position: ... }
        ↓
SURFACE SYSTEM: fire surface at explosion point
INTERACTION:    frost surface + fire explosion → steam cloud (Layer 2)
        ↓
EVENT: steam_created { position, radius }
        ↓
STATUS SYSTEM: nearby enemies get blinded (Layer 2)
TCE: room aura — ON: enemy_damaged IF: chain_depth < 3 → spread_to_nearest (Layer 1)
        ↓
CHAIN DEPTH 3 reached — chain terminates
        ↓
VISUAL QUEUE: choreographs all of the above across parallel tracks (Layer 3)
              players see: beam → impact → crystals → fire burst → steam bloom → blind
              each beat readable, each beat a consequence of the last
```

Nobody designed "frost beam + fire gear proc = steam blinds nearby enemies and chains to neighbors." It emerged from four rules interacting. This is the game.

---

No prerequisite chains. No workbench → planks → boots nonsense.

- Components found in The Wilds or produced by production buildings
- Bring components to a production building → combine them → get gear or trap
- Combination logic follows the effect + mod system — discovery not recipes
- Gear has 1-2 effects that are verbs, not stat numbers
- If an effect doesn't change how you play, it gets cut

---

## Production Buildings

- Built in captured rooms using resources from The Wilds
- Each building type produces a specific crafting material over time
- Also serve as crafting stations — combine components here
- Space is always scarce — you always want more than you have room for
- Capturing a new room = exciting building spree
- Buildings must be defended — losing a room loses its production
- Aesthetic goal: eldritch ritual chambers, arcane forges, dark arcane personality

---

## Trap System

- Placed in captured rooms forming the defensive gauntlet
- No walls — room geometry provides funneling, traps do the work
- All traps use the unified effect + mod system
- Require maintenance between waves — repair and replenish
- Maintenance = creative triage, not busywork
- Trap synergies are core (knockback into spike pit, frost slow into fire, etc.)
- Traps do not level up (v1)

---

## Gear System

- Found via exploration and drops in The Wilds, or crafted at production buildings
- No classes or roles — all players start identical, gear creates all divergence
- Every piece has 1-2 effects: meaningful verbs, never boring stat numbers
- Uses the unified effect + mod system
- New gear should immediately spark combination thinking
- Effects seen on traps can appear on gear — discovery transfers

---

## Progression

### Production (Camp / Captured Rooms)
- Buildings produce materials for gear and trap crafting
- More rooms = more building slots = more material variety
- Building choices reflect priorities — readable by teammates

### Stronghold Rooms
- Hand-crafted, must be cleared then captured
- Capture grants: new effect types, upgrade options, more build space
- Must be held — waves push inward through captured rooms if defenses fail
- Multiple push attempts intentional — scout, retreat, gear up, return

### Fallback Lines
- Each captured room is a defensive line
- Enemies breach inward sequentially
- Camp is last line — heavily fortified by late game, rarely reachable
- Nothing permanently lost — retaking always possible

---

## Multiplayer Architecture

- **Server authoritative** — server runs full deterministic simulation
- **Seeded RNG** — one instance, server is source of truth
- **WebSocket transport** — browser compatible, Godot 4 native
- **Simulation / View split** — server runs simulation only, no rendering
- **Event bus** — view layer on clients listens to events, never mutates simulation
- **Session lifecycle:**
  - Last player disconnects → serialize world to disk → pause
  - First player connects → deserialize → resume
- Players join anytime from browser — no install required

**Async co-op is a feature:**
- Base reflects everyone's contributions between sessions
- Damaged traps, depleted buildings, new constructions tell the story
- Shared stash for leaving gear and materials

---

## Failure States

- **Wave defense:** Breach → room lost, fall back to previous line
- **Production loss:** Lost room = buildings in it stop producing
- **Player death:** Respawn at camp, lose nothing except position
- **Camp falls:** Effectively ends the session — rare by design, always recoverable
- **No permanent loss** — friend's work is never erased, setbacks have recovery arcs

---

## Art Direction

- **Theme:** Eldritch, arcane, ritualistic, dark castle/fortress/dungeon
- **Style:** Pixel art preferred. High quality vector acceptable if it matches the tone.
- **Characters:** Robed ritualists. Dark fantasy silhouette.
- **Buildings:** Arcane ritual chambers, dark forges — functional and atmospheric
- **Priority:** Tone first, technical convenience second

---

## Map Generation

- **Stronghold:** Hand-crafted rooms, finite, escalating, final boss. Expansions go deeper.
- **Camp + captured rooms:** Player-built, persistent
- **The Wilds:** Procedurally generated with hand-crafted POI chunks (Spelunky-style) distributed throughout

### Enemy Design Philosophy

Enemies interact with the unified effect system as the game progresses — elemental affinities, resistances, their own spells. But complexity is added in layers:

- **v1:** Charge at player → melee attack when in range. Simple, dumb, satisfying to squish. Proves combat feel.
- **Later:** Elemental affinities and vulnerabilities (frost enemy weak to fire, etc.)
- **Later:** Ranged and spell-casting enemies
- **Stronghold depth:** Harder rooms introduce enemies with their own effect combinations

Enemy behavior complexity should track with stronghold depth — The Wilds has dumb chargers, deep stronghold rooms have casters and tacticians.

### v1 POI: Enemy Camp
Small camp of enemies in The Wilds. Passive until players enter detection range, then aggressive. Drops resources and gear components on clear. Simple, self-contained, tests combat and exploration feel simultaneously.

---

## Build Order (v1)

1. **Multiplayer foundation** — two browsers connected, character moving and synced. Highest risk, derisk first.
2. **Movement AND combat feel** — both must feel great before anything else. One spell (frost bolt), one enemy type. Juice relentlessly. Do not proceed until it genuinely feels good.
3. **Unified effect system** — one effect working on gear AND trap in the same codebase. Prove the architecture.
4. **Persistence** — serialize/deserialize world, server lifecycle (pause on empty, resume on join).
5. **Wave spawning** — fixed timer, enemies from stronghold direction, basic pathing through trap zone.
6. **One stronghold room** — push, clear, capture, hold, end to end.
7. **Enemy camp POI in The Wilds** — detection aggro, drops resources on clear, one production building, full mini loop.
8. **Content expansion** — more effects, mods, traps, rooms, gear, buildings.

**Rule:** Each step must be playable and fun before moving to the next. Never build infrastructure for systems that aren't fun yet.

---

## What This Game Is Not

- Not Terraria — not freeform creative expression, not exploration-as-reward
- Not Dome Keeper — not solo, not shallow defense
- Not Minecraft — no crafting chains, no survival busywork
- Not Overcooked — async ownership matters more than real-time coordination chaos

---

## Resolved Decisions Log
> A record of why things are the way they are.

- **No walls** — traps are toys, walls are chores. Room geometry handles funneling.
- **No classes** — gear creates all player divergence. Everyone starts identical.
- **No trap leveling (v1)** — keep scope tight, add later if needed.
- **Fixed wave timer** — constant pressure, visible countdown, no player-triggered delay.
- **Seeded deterministic RNG** — required for server authority and testing. One singleton, no scattered randf() calls.
- **Simulation/view decoupled** — headless server and automated testing depend on this. Non-negotiable.
- **Space always scarce** — capturing rooms should feel exciting. Never have more space than you want buildings.
- **Async co-op** — friend's work visible between sessions is a core design pillar, not an afterthought.
