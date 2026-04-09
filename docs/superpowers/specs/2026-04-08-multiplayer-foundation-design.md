# Multiplayer Foundation Design

Build order step 1. Two browsers connected via WebSocket to a headless server, characters moving and synced with smooth client-side prediction.

---

## Scope

A playable movement prototype:
- Headless Godot server, two browser clients connect via WebSocket
- Placeholder tile map arena with collision
- Smooth interpolated movement with client-side prediction
- No combat, no enemies, no lobby, no persistence

"Done" means:
1. Server starts headless, listens on WebSocket
2. Two browser tabs connect, each gets a player character
3. Moving in one tab is visible in the other, smooth and responsive
4. GUT tests pass for message encoding, snapshot diffing, movement, input buffering
5. Closing a tab removes that player from the other client's view

---

## Network Topology

Dedicated headless Godot server process. Clients connect via WebSocket. No peer-to-peer. Server is the single simulation authority.

### Connection Flow

```
Client opens browser -> connects WebSocket to server:port
  -> Server sends handshake: { server_tick, world_seed, player_id }
  -> Server sends full state snapshot (one-time baseline)
  -> Client enters interpolation loop
  -> Client starts sending input at 20Hz
```

### Disconnection

Server removes player entity, notifies other clients via next snapshot delta. No reconnection-with-state in v1 -- reconnecting is a fresh connect (new full snapshot, resume play).

### Player Join Mid-Session

Same as initial connect -- full snapshot gives the joining client everything it needs. No replay, no special case.

### Server Lifecycle

Server starts, listens on a port, accepts connections. No lobby, no session management. Run server, open two browser tabs, you're in.

---

## Security

### What Server Authority Gives Us For Free

- Server assigns `player_id` on connect -- clients don't choose or claim an identity
- Clients can only send `player_input` (a direction vector) -- not state mutations
- Server validates all inputs and simulates the result
- No client can teleport, spawn items, damage enemies, or modify world state

### Active Measures (This Step)

- **Max player cap:** Reject WebSocket connections beyond the limit
- **Rate-limit connections per IP:** Prevent connection flooding
- **Connection-to-player mapping:** Server maps each WebSocket connection to a player_id internally. Client-to-server messages contain no player ID -- the server resolves identity from the connection. Unrecognized connections are ignored.
- **Message validation:** Malformed messages are dropped, not processed

### Deferred

- Authentication (accounts, tokens) -- when persistence arrives
- Anti-bot -- when there's an economy or competitive advantage
- Encryption (WSS) -- deploy-time config

---

## Message Layer

All game code sends and receives typed message objects through a `NetMessage` abstraction. No code outside this layer touches serialization format.

### Two Wire Formats, One Interface

| Channel | Format | Used for | Why |
|---------|--------|----------|-----|
| State | Binary (PackedByteArray) | Snapshots, position deltas, entity updates | High frequency, bandwidth matters |
| Event | JSON | Player join/leave, handshake | Low frequency, debuggability matters |

The game code doesn't know which format is used. The abstraction layer handles encoding/decoding.

### Message Types

| Message | Direction | Format | Contents |
|---------|-----------|--------|----------|
| `handshake` | S->C | JSON | server_tick, player_id, world_seed |
| `full_snapshot` | S->C | Binary | All entity positions + states |
| `delta_snapshot` | S->C | Binary | Changed entities since client's last ACK |
| `snapshot_ack` | C->S | Binary | Last received server tick |
| `player_input` | C->S | Binary | tick, direction_x, direction_y, input_seq |
| `player_joined` | S->C | JSON | player_id, spawn_position |
| `player_left` | S->C | JSON | player_id |

### Binary Snapshot Structure (Per Entity)

```
[entity_id: u16][x: f32][y: f32][flags: u8]
```

10 bytes per entity. Frame header contains tick number and entity count.

### Player Input Structure

```
[tick: u32][direction_x: f16][direction_y: f16][input_seq: u16]
```

No player ID on the wire. Server resolves identity from the connection.

### ACK Mechanism

Client sends `snapshot_ack` with the tick of the last snapshot it fully received. Server uses this as the diff baseline for that client's next delta. If no ACK received within 60 ticks (3 seconds), server falls back to a full snapshot.

---

## Server Simulation Loop

Fixed 20Hz tick loop (50ms per tick).

### Tick Phases

```
1. Receive & queue client inputs
2. Apply inputs to player entities
3. Simulate movement + collision (move_and_slide)
4. Build delta snapshot per client (diff against their last ACK)
5. Send deltas
6. Process ACKs, update baselines
```

### Input Queue

Inputs arrive asynchronously between ticks. Server buffers them and processes the batch at the start of each tick. Multiple inputs from the same player in one tick are applied in sequence order.

### Late Inputs

If an input arrives tagged for a tick that already passed, apply it to the current tick. Server time moves forward only -- never re-simulate past ticks.

### Tick Timing

Loop targets 50ms per tick. If a tick overruns, the next tick runs immediately (no skipping). If it finishes early, it sleeps the remainder. Standard fixed-timestep pattern.

### What Runs This Step

Player movement with collision against a TileMap. No enemies, no spells, no effects. The loop structure is ready for those -- they'll slot into phase 3.

---

## Client-Side Prediction & Reconciliation

### Three Concurrent Processes

**1. Predict locally on input**

Player presses a key. Client immediately moves the character locally using the same physics as the server (`move_and_slide`). Sends the input to the server with a sequence number. Stores the prediction: `{ seq, input, predicted_position }`.

**2. Interpolate everything else**

Other players (and later enemies, projectiles, etc.) are rendered by interpolating between the two most recent server snapshots. The client renders these entities ~50ms in the past. At ARPG speeds this delay is imperceptible, but movement looks smooth instead of jerky 20Hz steps.

**3. Reconcile when server snapshots arrive**

Server snapshot arrives containing the player's authoritative position and the last processed input sequence number.

- Discard all stored predictions up to that sequence
- Compare server position to what was predicted for that sequence
- **Small divergence** (< threshold): blend visual position toward server position over ~100-150ms. Player never notices.
- **Large divergence** (e.g. knockback, teleport): snap immediately. Large corrections should feel abrupt -- blending them looks like rubber-banding.

The logical position for re-applying unacknowledged inputs always uses the server state exactly. Smoothing is visual only.

### Why This Works

99% of the time, prediction matches the server because both run `move_and_slide` with the same input. Reconciliation only kicks in when something unexpected happened server-side. Godot's physics is not guaranteed deterministic across platforms, but small divergences are exactly what the blend/reconcile system handles.

---

## Delta Compression

Clients receive delta-compressed snapshots, not full world state every tick.

### How It Works

1. Server tracks the last snapshot each client acknowledged
2. Each tick, diff current state against that client's baseline
3. Send only entities that changed since their last ACK
4. Unchanged entities cost zero bytes

### Bandwidth Estimate (Busy Tick)

50 of 200 enemies moved, a spell went off:

| What | Size |
|------|------|
| 50 enemy position deltas | 500 B |
| 150 unchanged enemies | 0 B |
| 3 new projectiles | 60 B |
| 2 status changes | 20 B |
| Frame header | 8 B |
| **Total** | **~590 B** |

590 bytes x 20 ticks = ~12 KB/s per client. Eight clients = ~94 KB/s upstream.

### Reserve Optimizations (Not Built Yet)

- Spatial relevance -- skip entities far from a client's camera
- Quantization -- half-precision floats, fixed-point positions
- Priority accumulator -- less important entities update less frequently

---

## World & Collision

### TileMap

- Single placeholder arena, ~30x20 tiles, 16x16 pixel tiles
- Floor tiles with a wall border
- Enough to feel like a room, not an infinite void

### Collision

Uses Godot's built-in physics: `CharacterBody2D` with `move_and_slide`.

- Server scene has collision shapes from the TileMap (no visual tiles)
- Client scene has both collision shapes (for prediction) and visual tiles
- Collision layers/masks separate player vs wall (extensible for enemies later)

Godot's physics is not deterministic across platforms. This is fine -- our snapshot interpolation architecture tolerates prediction mismatch by design. The reconciliation system smoothly corrects any divergence.

---

## Project Structure

```
/godot
  /autoloads
    rng.gd                    <- exists
    event_bus.gd              <- exists

  /simulation
    /entities
      player_entity.gd        <- position, velocity, player_id -- no visuals
    /systems
      movement_system.gd      <- applies input -> velocity -> position + collision
    /network
      net_server.gd           <- WebSocket listener, tick loop, snapshot building
      net_client.gd           <- WebSocket client, input sending, prediction
      net_message.gd          <- abstraction: typed messages <-> binary/JSON
      snapshot.gd             <- serialize/deserialize/diff entity state
      input_buffer.gd         <- queues and sequences player inputs

  /view
    /world
      player_view.gd          <- sprite, interpolation, visual reconciliation
      world_view.gd           <- TileMap, spawns/removes player views
    /ui
      connection_ui.gd        <- server address, connect button, status

  /shared
    /network
      message_types.gd        <- enum/constants for message IDs

  /tests
    /entities
      test_player_entity.gd
    /systems
      test_movement_system.gd
    /network
      test_net_message.gd     <- round-trip encode/decode for every message type
      test_snapshot.gd        <- full snapshot, delta diff, delta apply
      test_input_buffer.gd    <- ordering, late inputs, sequence gaps
    gut_config.json
```

### Key Decisions

- Network code lives in `/simulation` -- it's logic, runs on the headless server
- `message_types.gd` is in `/shared` -- both client and server reference it
- `player_entity.gd` is pure data. `player_view.gd` in the view layer follows it.
- Tests mirror the simulation structure, run headless via GUT

---

## Entry Points

| Scene | Loads | Run command |
|-------|-------|-------------|
| `server.tscn` | Simulation + network server + collision (no view) | `godot --headless --main-pack hexvael.pck -- --server --port 9050` |
| `client.tscn` | Simulation (for prediction) + network client + full view | Export to web, open in browser. Or F5 in editor for desktop. |

### Server CLI Args

- `--server` -- run in server mode
- `--port <N>` -- listen port (default 9050)

### Dev Session

```
Terminal 1:  run headless server
Browser tab 1:  open localhost, connect
Browser tab 2:  open localhost, connect
-> two characters moving in the same arena, synced
```

### GUT Tests

```
godot --headless -s addons/gut/gut_cmdline.gd
```

Fully headless, no display needed.
