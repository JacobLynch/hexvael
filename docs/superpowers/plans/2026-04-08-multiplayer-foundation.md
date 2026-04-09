# Multiplayer Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two browser clients connected via WebSocket to a headless Godot server, with player characters moving and syncing via snapshot interpolation and client-side prediction.

**Architecture:** Server-authoritative with 20Hz tick loop. Clients send inputs, server simulates and sends delta-compressed snapshots. Local player uses client-side prediction with reconciliation. Remote players interpolate between snapshots. Binary format for high-frequency state, JSON for low-frequency events.

**Tech Stack:** Godot 4.6, GDScript, WebSocket (TCPServer + WebSocketPeer), GUT testing framework, CharacterBody2D for physics.

**Spec:** `docs/superpowers/specs/2026-04-08-multiplayer-foundation-design.md`

---

## Task 1: Install GUT and Configure Test Runner

**Files:**
- Create: `godot/tests/gut_config.json`
- Modify: `godot/project.godot`

GUT (Godot Unit Test) is the testing framework. Install it and verify tests run headless.

- [ ] **Step 1: Install GUT plugin**

Download GUT from the Godot Asset Library or clone it. The addon must exist at `godot/addons/gut/`.

Run from the `godot/` directory:
```bash
cd godot && git clone https://github.com/bitwes/Gut.git addons/gut_repo && mv addons/gut_repo/addons/gut addons/gut && rm -rf addons/gut_repo
```

- [ ] **Step 2: Create GUT config**

Create `godot/tests/gut_config.json`:
```json
{
    "dirs": ["res://tests/"],
    "include_subdirs": true,
    "prefix": "test_",
    "suffix": ".gd",
    "log_level": 1
}
```

- [ ] **Step 3: Create a smoke test to verify GUT works**

Create `godot/tests/test_smoke.gd`:
```gdscript
extends GutTest

func test_gut_works():
    assert_true(true, "GUT is working")
```

- [ ] **Step 4: Enable the GUT plugin in project.godot**

Add to the `[editor_plugins]` section of `godot/project.godot`:
```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/gut/plugin.cfg")
```

- [ ] **Step 5: Run the smoke test headless**

Run from the `godot/` directory:
```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: 1 test passes, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add addons/gut tests/test_smoke.gd tests/gut_config.json project.godot
git commit -m "Add GUT testing framework and smoke test"
```

---

## Task 2: Message Types Constants

**Files:**
- Create: `godot/shared/network/message_types.gd`

Shared constants for message IDs used by both server and client. This is the vocabulary of the protocol.

- [ ] **Step 1: Create message_types.gd**

Create `godot/shared/network/message_types.gd`:
```gdscript
class_name MessageTypes

# Message type IDs — first byte of every binary message
enum Binary {
    FULL_SNAPSHOT = 1,
    DELTA_SNAPSHOT = 2,
    SNAPSHOT_ACK = 3,
    PLAYER_INPUT = 4,
}

# JSON message types — value of the "type" key
class JSON:
    const HANDSHAKE = "handshake"
    const PLAYER_JOINED = "player_joined"
    const PLAYER_LEFT = "player_left"

# Entity flags (bitfield in snapshot entity data)
enum EntityFlags {
    NONE = 0,
    MOVING = 1,       # Entity is currently moving
    REMOVED = 2,      # Entity was removed (delta only)
}

# Binary layout sizes in bytes
class Layout:
    # Snapshot frame header: [msg_type: u8][tick: u32][entity_count: u16]
    const SNAPSHOT_HEADER_SIZE = 7
    # Per-entity: [entity_id: u16][x: f32][y: f32][flags: u8]
    const ENTITY_SIZE = 11
    # Player input: [msg_type: u8][tick: u32][dir_x: f32][dir_y: f32][input_seq: u16]
    const INPUT_SIZE = 15
    # Snapshot ACK: [msg_type: u8][tick: u32]
    const ACK_SIZE = 5

# Limits
const MAX_PLAYERS = 8
const TICK_RATE = 20
const TICK_INTERVAL_MS = 50
const ACK_TIMEOUT_TICKS = 60  # 3 seconds — fall back to full snapshot
const SPAWN_POSITION = Vector2(240.0, 160.0)  # Center of 30x20 arena
```

- [ ] **Step 2: Commit**

```bash
git add shared/network/message_types.gd
git commit -m "Add shared message type constants for network protocol"
```

---

## Task 3: NetMessage Abstraction Layer

**Files:**
- Create: `godot/simulation/network/net_message.gd`
- Create: `godot/tests/network/test_net_message.gd`

The serialization abstraction. Game code sends/receives typed dictionaries. This layer handles binary/JSON encoding. No other code touches wire format.

- [ ] **Step 1: Write failing tests for binary encoding round-trips**

Create `godot/tests/network/test_net_message.gd`:
```gdscript
extends GutTest

var NetMessage = preload("res://simulation/network/net_message.gd")


func test_encode_decode_player_input():
    var msg = {
        "type": MessageTypes.Binary.PLAYER_INPUT,
        "tick": 42,
        "direction": Vector2(0.707, -0.707),
        "input_seq": 15,
    }
    var bytes = NetMessage.encode(msg)
    assert_eq(bytes.size(), MessageTypes.Layout.INPUT_SIZE, "Input message should be %d bytes" % MessageTypes.Layout.INPUT_SIZE)

    var decoded = NetMessage.decode_binary(bytes)
    assert_eq(decoded["type"], MessageTypes.Binary.PLAYER_INPUT)
    assert_eq(decoded["tick"], 42)
    assert_almost_eq(decoded["direction"].x, 0.707, 0.001)
    assert_almost_eq(decoded["direction"].y, -0.707, 0.001)
    assert_eq(decoded["input_seq"], 15)


func test_encode_decode_snapshot_ack():
    var msg = {
        "type": MessageTypes.Binary.SNAPSHOT_ACK,
        "tick": 1000,
    }
    var bytes = NetMessage.encode(msg)
    assert_eq(bytes.size(), MessageTypes.Layout.ACK_SIZE)

    var decoded = NetMessage.decode_binary(bytes)
    assert_eq(decoded["type"], MessageTypes.Binary.SNAPSHOT_ACK)
    assert_eq(decoded["tick"], 1000)


func test_encode_decode_full_snapshot():
    var entities = [
        {"entity_id": 1, "position": Vector2(100.5, 200.75), "flags": MessageTypes.EntityFlags.MOVING},
        {"entity_id": 2, "position": Vector2(300.0, 400.0), "flags": MessageTypes.EntityFlags.NONE},
    ]
    var msg = {
        "type": MessageTypes.Binary.FULL_SNAPSHOT,
        "tick": 500,
        "entities": entities,
    }
    var bytes = NetMessage.encode(msg)
    var expected_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE + (2 * MessageTypes.Layout.ENTITY_SIZE)
    assert_eq(bytes.size(), expected_size)

    var decoded = NetMessage.decode_binary(bytes)
    assert_eq(decoded["type"], MessageTypes.Binary.FULL_SNAPSHOT)
    assert_eq(decoded["tick"], 500)
    assert_eq(decoded["entities"].size(), 2)
    assert_eq(decoded["entities"][0]["entity_id"], 1)
    assert_almost_eq(decoded["entities"][0]["position"].x, 100.5, 0.01)
    assert_almost_eq(decoded["entities"][0]["position"].y, 200.75, 0.01)
    assert_eq(decoded["entities"][0]["flags"], MessageTypes.EntityFlags.MOVING)


func test_encode_decode_delta_snapshot():
    var entities = [
        {"entity_id": 1, "position": Vector2(105.0, 205.0), "flags": MessageTypes.EntityFlags.MOVING},
    ]
    var msg = {
        "type": MessageTypes.Binary.DELTA_SNAPSHOT,
        "tick": 501,
        "entities": entities,
    }
    var bytes = NetMessage.encode(msg)
    var decoded = NetMessage.decode_binary(bytes)
    assert_eq(decoded["type"], MessageTypes.Binary.DELTA_SNAPSHOT)
    assert_eq(decoded["tick"], 501)
    assert_eq(decoded["entities"].size(), 1)


func test_encode_decode_json_handshake():
    var msg = {
        "type": MessageTypes.JSON.HANDSHAKE,
        "server_tick": 100,
        "player_id": 3,
        "world_seed": 12345,
    }
    var text = NetMessage.encode_json(msg)
    var decoded = NetMessage.decode_json(text)
    assert_eq(decoded["type"], MessageTypes.JSON.HANDSHAKE)
    assert_eq(decoded["server_tick"], 100)
    assert_eq(decoded["player_id"], 3)
    assert_eq(decoded["world_seed"], 12345)


func test_encode_decode_json_player_joined():
    var msg = {
        "type": MessageTypes.JSON.PLAYER_JOINED,
        "player_id": 5,
        "spawn_position": {"x": 240.0, "y": 160.0},
    }
    var text = NetMessage.encode_json(msg)
    var decoded = NetMessage.decode_json(text)
    assert_eq(decoded["type"], MessageTypes.JSON.PLAYER_JOINED)
    assert_eq(decoded["player_id"], 5)
    assert_almost_eq(float(decoded["spawn_position"]["x"]), 240.0, 0.01)


func test_encode_decode_json_player_left():
    var msg = {
        "type": MessageTypes.JSON.PLAYER_LEFT,
        "player_id": 5,
    }
    var text = NetMessage.encode_json(msg)
    var decoded = NetMessage.decode_json(text)
    assert_eq(decoded["type"], MessageTypes.JSON.PLAYER_LEFT)
    assert_eq(decoded["player_id"], 5)


func test_decode_binary_rejects_malformed_data():
    var garbage = PackedByteArray([255, 0, 0])
    var decoded = NetMessage.decode_binary(garbage)
    assert_null(decoded, "Malformed binary should return null")


func test_decode_binary_rejects_truncated_input():
    # Valid type byte for PLAYER_INPUT but too short
    var truncated = PackedByteArray([MessageTypes.Binary.PLAYER_INPUT, 0, 0])
    var decoded = NetMessage.decode_binary(truncated)
    assert_null(decoded, "Truncated message should return null")


func test_empty_snapshot():
    var msg = {
        "type": MessageTypes.Binary.FULL_SNAPSHOT,
        "tick": 1,
        "entities": [],
    }
    var bytes = NetMessage.encode(msg)
    assert_eq(bytes.size(), MessageTypes.Layout.SNAPSHOT_HEADER_SIZE)

    var decoded = NetMessage.decode_binary(bytes)
    assert_eq(decoded["entities"].size(), 0)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All `test_net_message` tests FAIL (cannot preload `net_message.gd`).

- [ ] **Step 3: Implement net_message.gd**

Create `godot/simulation/network/net_message.gd`:
```gdscript
class_name NetMessage


# --- Binary encoding ---

static func encode(msg: Dictionary) -> PackedByteArray:
    var type: int = msg["type"]
    match type:
        MessageTypes.Binary.PLAYER_INPUT:
            return _encode_player_input(msg)
        MessageTypes.Binary.SNAPSHOT_ACK:
            return _encode_snapshot_ack(msg)
        MessageTypes.Binary.FULL_SNAPSHOT, MessageTypes.Binary.DELTA_SNAPSHOT:
            return _encode_snapshot(msg)
    push_error("NetMessage.encode: unknown binary type %d" % type)
    return PackedByteArray()


static func decode_binary(bytes: PackedByteArray) -> Variant:
    if bytes.size() < 1:
        return null
    var type: int = bytes.decode_u8(0)
    match type:
        MessageTypes.Binary.PLAYER_INPUT:
            return _decode_player_input(bytes)
        MessageTypes.Binary.SNAPSHOT_ACK:
            return _decode_snapshot_ack(bytes)
        MessageTypes.Binary.FULL_SNAPSHOT, MessageTypes.Binary.DELTA_SNAPSHOT:
            return _decode_snapshot(bytes, type)
    return null


# --- JSON encoding ---

static func encode_json(msg: Dictionary) -> String:
    return JSON.stringify(msg)


static func decode_json(text: String) -> Variant:
    var result = JSON.parse_string(text)
    if result == null:
        push_error("NetMessage.decode_json: failed to parse: %s" % text)
    return result


# --- Private: Player Input ---

static func _encode_player_input(msg: Dictionary) -> PackedByteArray:
    var buf = PackedByteArray()
    buf.resize(MessageTypes.Layout.INPUT_SIZE)
    var dir: Vector2 = msg["direction"]
    buf.encode_u8(0, MessageTypes.Binary.PLAYER_INPUT)
    buf.encode_u32(1, msg["tick"])
    buf.encode_float(5, dir.x)
    buf.encode_float(9, dir.y)
    buf.encode_u16(13, msg["input_seq"])
    return buf


static func _decode_player_input(bytes: PackedByteArray) -> Variant:
    if bytes.size() < MessageTypes.Layout.INPUT_SIZE:
        return null
    return {
        "type": MessageTypes.Binary.PLAYER_INPUT,
        "tick": bytes.decode_u32(1),
        "direction": Vector2(bytes.decode_float(5), bytes.decode_float(9)),
        "input_seq": bytes.decode_u16(13),
    }


# --- Private: Snapshot ACK ---

static func _encode_snapshot_ack(msg: Dictionary) -> PackedByteArray:
    var buf = PackedByteArray()
    buf.resize(MessageTypes.Layout.ACK_SIZE)
    buf.encode_u8(0, MessageTypes.Binary.SNAPSHOT_ACK)
    buf.encode_u32(1, msg["tick"])
    return buf


static func _decode_snapshot_ack(bytes: PackedByteArray) -> Variant:
    if bytes.size() < MessageTypes.Layout.ACK_SIZE:
        return null
    return {
        "type": MessageTypes.Binary.SNAPSHOT_ACK,
        "tick": bytes.decode_u32(1),
    }


# --- Private: Snapshots (full + delta use same format) ---

static func _encode_snapshot(msg: Dictionary) -> PackedByteArray:
    var entities: Array = msg["entities"]
    var header_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE
    var entity_size = MessageTypes.Layout.ENTITY_SIZE
    var buf = PackedByteArray()
    buf.resize(header_size + entities.size() * entity_size)
    buf.encode_u8(0, msg["type"])
    buf.encode_u32(1, msg["tick"])
    buf.encode_u16(5, entities.size())
    for i in range(entities.size()):
        var offset = header_size + i * entity_size
        var ent = entities[i]
        var pos: Vector2 = ent["position"]
        buf.encode_u16(offset, ent["entity_id"])
        buf.encode_float(offset + 2, pos.x)
        buf.encode_float(offset + 6, pos.y)
        buf.encode_u8(offset + 10, ent["flags"])
    return buf


static func _decode_snapshot(bytes: PackedByteArray, type: int) -> Variant:
    var header_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE
    var entity_size = MessageTypes.Layout.ENTITY_SIZE
    if bytes.size() < header_size:
        return null
    var entity_count = bytes.decode_u16(5)
    if bytes.size() < header_size + entity_count * entity_size:
        return null
    var entities: Array = []
    for i in range(entity_count):
        var offset = header_size + i * entity_size
        entities.append({
            "entity_id": bytes.decode_u16(offset),
            "position": Vector2(bytes.decode_float(offset + 2), bytes.decode_float(offset + 6)),
            "flags": bytes.decode_u8(offset + 10),
        })
    return {
        "type": type,
        "tick": bytes.decode_u32(1),
        "entities": entities,
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All `test_net_message` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add simulation/network/net_message.gd tests/network/test_net_message.gd
git commit -m "Add NetMessage abstraction layer with binary and JSON encoding"
```

---

## Task 4: Input Buffer

**Files:**
- Create: `godot/simulation/network/input_buffer.gd`
- Create: `godot/tests/network/test_input_buffer.gd`

Buffers incoming player inputs between ticks, handles sequencing and late arrival.

- [ ] **Step 1: Write failing tests**

Create `godot/tests/network/test_input_buffer.gd`:
```gdscript
extends GutTest

var InputBuffer = preload("res://simulation/network/input_buffer.gd")

var _buffer: InputBuffer


func before_each():
    _buffer = InputBuffer.new()


func test_add_and_drain_inputs():
    _buffer.add_input(1, {
        "tick": 10, "direction": Vector2.RIGHT, "input_seq": 1,
    })
    _buffer.add_input(1, {
        "tick": 10, "direction": Vector2.UP, "input_seq": 2,
    })
    var inputs = _buffer.drain_inputs_for_player(1)
    assert_eq(inputs.size(), 2)
    assert_eq(inputs[0]["input_seq"], 1, "Should be in sequence order")
    assert_eq(inputs[1]["input_seq"], 2)


func test_drain_clears_buffer():
    _buffer.add_input(1, {
        "tick": 10, "direction": Vector2.RIGHT, "input_seq": 1,
    })
    _buffer.drain_inputs_for_player(1)
    var inputs = _buffer.drain_inputs_for_player(1)
    assert_eq(inputs.size(), 0, "Buffer should be empty after drain")


func test_inputs_sorted_by_sequence():
    _buffer.add_input(1, {
        "tick": 10, "direction": Vector2.RIGHT, "input_seq": 3,
    })
    _buffer.add_input(1, {
        "tick": 10, "direction": Vector2.UP, "input_seq": 1,
    })
    _buffer.add_input(1, {
        "tick": 10, "direction": Vector2.LEFT, "input_seq": 2,
    })
    var inputs = _buffer.drain_inputs_for_player(1)
    assert_eq(inputs[0]["input_seq"], 1)
    assert_eq(inputs[1]["input_seq"], 2)
    assert_eq(inputs[2]["input_seq"], 3)


func test_separate_players():
    _buffer.add_input(1, {
        "tick": 10, "direction": Vector2.RIGHT, "input_seq": 1,
    })
    _buffer.add_input(2, {
        "tick": 10, "direction": Vector2.LEFT, "input_seq": 1,
    })
    var p1 = _buffer.drain_inputs_for_player(1)
    var p2 = _buffer.drain_inputs_for_player(2)
    assert_eq(p1.size(), 1)
    assert_eq(p2.size(), 1)
    assert_eq(p1[0]["direction"], Vector2.RIGHT)
    assert_eq(p2[0]["direction"], Vector2.LEFT)


func test_drain_unknown_player_returns_empty():
    var inputs = _buffer.drain_inputs_for_player(99)
    assert_eq(inputs.size(), 0)


func test_duplicate_sequence_ignored():
    _buffer.add_input(1, {
        "tick": 10, "direction": Vector2.RIGHT, "input_seq": 1,
    })
    _buffer.add_input(1, {
        "tick": 10, "direction": Vector2.LEFT, "input_seq": 1,
    })
    var inputs = _buffer.drain_inputs_for_player(1)
    assert_eq(inputs.size(), 1, "Duplicate seq should be ignored")


func test_remove_player():
    _buffer.add_input(1, {
        "tick": 10, "direction": Vector2.RIGHT, "input_seq": 1,
    })
    _buffer.remove_player(1)
    var inputs = _buffer.drain_inputs_for_player(1)
    assert_eq(inputs.size(), 0)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All `test_input_buffer` tests FAIL.

- [ ] **Step 3: Implement input_buffer.gd**

Create `godot/simulation/network/input_buffer.gd`:
```gdscript
class_name InputBuffer

# player_id -> Array of input dicts
var _buffers: Dictionary = {}
# player_id -> Dictionary of seen sequence numbers (for dedup)
var _seen_seqs: Dictionary = {}


func add_input(player_id: int, input: Dictionary) -> void:
    var seq: int = input["input_seq"]
    if not _seen_seqs.has(player_id):
        _seen_seqs[player_id] = {}
    if _seen_seqs[player_id].has(seq):
        return  # duplicate
    _seen_seqs[player_id][seq] = true
    if not _buffers.has(player_id):
        _buffers[player_id] = []
    _buffers[player_id].append(input)


func drain_inputs_for_player(player_id: int) -> Array:
    if not _buffers.has(player_id):
        return []
    var inputs: Array = _buffers[player_id]
    inputs.sort_custom(func(a, b): return a["input_seq"] < b["input_seq"])
    _buffers[player_id] = []
    _seen_seqs[player_id] = {}
    return inputs


func remove_player(player_id: int) -> void:
    _buffers.erase(player_id)
    _seen_seqs.erase(player_id)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All `test_input_buffer` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add simulation/network/input_buffer.gd tests/network/test_input_buffer.gd
git commit -m "Add InputBuffer with sequencing, dedup, and per-player drain"
```

---

## Task 5: Snapshot System

**Files:**
- Create: `godot/simulation/network/snapshot.gd`
- Create: `godot/tests/network/test_snapshot.gd`

Manages world state snapshots: capture current state, diff against a baseline, and apply deltas.

- [ ] **Step 1: Write failing tests**

Create `godot/tests/network/test_snapshot.gd`:
```gdscript
extends GutTest

var Snapshot = preload("res://simulation/network/snapshot.gd")


func _make_entity(id: int, x: float, y: float, flags: int = 0) -> Dictionary:
    return {"entity_id": id, "position": Vector2(x, y), "flags": flags}


func test_capture_entities():
    var snap = Snapshot.new()
    snap.tick = 10
    snap.entities = {
        1: _make_entity(1, 100.0, 200.0),
        2: _make_entity(2, 300.0, 400.0),
    }
    assert_eq(snap.tick, 10)
    assert_eq(snap.entities.size(), 2)
    assert_eq(snap.entities[1]["position"], Vector2(100.0, 200.0))


func test_diff_detects_moved_entity():
    var baseline = Snapshot.new()
    baseline.tick = 10
    baseline.entities = {
        1: _make_entity(1, 100.0, 200.0),
        2: _make_entity(2, 300.0, 400.0),
    }
    var current = Snapshot.new()
    current.tick = 11
    current.entities = {
        1: _make_entity(1, 105.0, 200.0, MessageTypes.EntityFlags.MOVING),
        2: _make_entity(2, 300.0, 400.0),
    }
    var delta = Snapshot.diff(baseline, current)
    assert_eq(delta.size(), 1, "Only entity 1 moved")
    assert_eq(delta[0]["entity_id"], 1)
    assert_almost_eq(delta[0]["position"].x, 105.0, 0.01)


func test_diff_detects_new_entity():
    var baseline = Snapshot.new()
    baseline.tick = 10
    baseline.entities = {
        1: _make_entity(1, 100.0, 200.0),
    }
    var current = Snapshot.new()
    current.tick = 11
    current.entities = {
        1: _make_entity(1, 100.0, 200.0),
        2: _make_entity(2, 300.0, 400.0),
    }
    var delta = Snapshot.diff(baseline, current)
    assert_eq(delta.size(), 1, "Entity 2 is new")
    assert_eq(delta[0]["entity_id"], 2)


func test_diff_detects_removed_entity():
    var baseline = Snapshot.new()
    baseline.tick = 10
    baseline.entities = {
        1: _make_entity(1, 100.0, 200.0),
        2: _make_entity(2, 300.0, 400.0),
    }
    var current = Snapshot.new()
    current.tick = 11
    current.entities = {
        1: _make_entity(1, 100.0, 200.0),
    }
    var delta = Snapshot.diff(baseline, current)
    assert_eq(delta.size(), 1, "Entity 2 removed")
    assert_eq(delta[0]["entity_id"], 2)
    assert_eq(delta[0]["flags"], MessageTypes.EntityFlags.REMOVED)


func test_diff_empty_when_no_changes():
    var snap = Snapshot.new()
    snap.tick = 10
    snap.entities = {
        1: _make_entity(1, 100.0, 200.0),
    }
    var same = Snapshot.new()
    same.tick = 11
    same.entities = {
        1: _make_entity(1, 100.0, 200.0),
    }
    var delta = Snapshot.diff(snap, same)
    assert_eq(delta.size(), 0)


func test_apply_delta_updates_position():
    var snap = Snapshot.new()
    snap.tick = 10
    snap.entities = {
        1: _make_entity(1, 100.0, 200.0),
    }
    var delta_entities = [_make_entity(1, 110.0, 210.0, MessageTypes.EntityFlags.MOVING)]
    snap.apply_delta(11, delta_entities)
    assert_eq(snap.tick, 11)
    assert_almost_eq(snap.entities[1]["position"].x, 110.0, 0.01)


func test_apply_delta_adds_new_entity():
    var snap = Snapshot.new()
    snap.tick = 10
    snap.entities = {}
    var delta_entities = [_make_entity(5, 50.0, 60.0)]
    snap.apply_delta(11, delta_entities)
    assert_eq(snap.entities.size(), 1)
    assert_true(snap.entities.has(5))


func test_apply_delta_removes_entity():
    var snap = Snapshot.new()
    snap.tick = 10
    snap.entities = {
        1: _make_entity(1, 100.0, 200.0),
    }
    var delta_entities = [{"entity_id": 1, "position": Vector2.ZERO, "flags": MessageTypes.EntityFlags.REMOVED}]
    snap.apply_delta(11, delta_entities)
    assert_false(snap.entities.has(1))


func test_to_entity_array():
    var snap = Snapshot.new()
    snap.tick = 10
    snap.entities = {
        1: _make_entity(1, 100.0, 200.0),
        3: _make_entity(3, 300.0, 400.0),
    }
    var arr = snap.to_entity_array()
    assert_eq(arr.size(), 2)


func test_duplicate_creates_independent_copy():
    var snap = Snapshot.new()
    snap.tick = 10
    snap.entities = {
        1: _make_entity(1, 100.0, 200.0),
    }
    var copy = snap.duplicate_snapshot()
    copy.entities[1]["position"] = Vector2(999.0, 999.0)
    assert_almost_eq(snap.entities[1]["position"].x, 100.0, 0.01, "Original should be unchanged")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All `test_snapshot` tests FAIL.

- [ ] **Step 3: Implement snapshot.gd**

Create `godot/simulation/network/snapshot.gd`:
```gdscript
class_name Snapshot

var tick: int = 0
# entity_id -> { "entity_id": int, "position": Vector2, "flags": int }
var entities: Dictionary = {}


# Returns an array of entity dicts that changed between baseline and current.
# Removed entities appear with the REMOVED flag.
static func diff(baseline: Snapshot, current: Snapshot) -> Array:
    var changes: Array = []

    # Check for changed or new entities
    for eid in current.entities:
        if not baseline.entities.has(eid):
            changes.append(current.entities[eid].duplicate())
        else:
            var base_ent = baseline.entities[eid]
            var curr_ent = current.entities[eid]
            if not base_ent["position"].is_equal_approx(curr_ent["position"]) or base_ent["flags"] != curr_ent["flags"]:
                changes.append(curr_ent.duplicate())

    # Check for removed entities
    for eid in baseline.entities:
        if not current.entities.has(eid):
            changes.append({
                "entity_id": eid,
                "position": Vector2.ZERO,
                "flags": MessageTypes.EntityFlags.REMOVED,
            })

    return changes


# Applies a delta (array of entity dicts) to this snapshot in-place.
func apply_delta(new_tick: int, delta_entities: Array) -> void:
    tick = new_tick
    for ent in delta_entities:
        var eid: int = ent["entity_id"]
        if ent["flags"] & MessageTypes.EntityFlags.REMOVED:
            entities.erase(eid)
        else:
            entities[eid] = ent.duplicate()


# Returns all entities as a flat array (for NetMessage encoding).
func to_entity_array() -> Array:
    return entities.values()


# Returns an independent deep copy of this snapshot.
func duplicate_snapshot() -> Snapshot:
    var copy = Snapshot.new()
    copy.tick = tick
    for eid in entities:
        copy.entities[eid] = entities[eid].duplicate()
    return copy
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All `test_snapshot` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add simulation/network/snapshot.gd tests/network/test_snapshot.gd
git commit -m "Add Snapshot system with diff, apply_delta, and duplication"
```

---

## Task 6: Player Entity

**Files:**
- Create: `godot/simulation/entities/player_entity.gd`
- Create: `godot/simulation/entities/player_entity.tscn`
- Create: `godot/tests/entities/test_player_entity.gd`

Pure simulation-side player. CharacterBody2D with collision shape, no visuals. Holds player state and applies movement.

- [ ] **Step 1: Write failing tests**

Create `godot/tests/entities/test_player_entity.gd`:
```gdscript
extends GutTest

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func test_initial_state():
    var player = PlayerEntityScene.instantiate()
    add_child_autofree(player)
    assert_eq(player.player_id, -1, "Default player_id should be -1")
    assert_eq(player.velocity, Vector2.ZERO)


func test_initialize_sets_id_and_position():
    var player = PlayerEntityScene.instantiate()
    add_child_autofree(player)
    player.initialize(5, Vector2(100.0, 200.0))
    assert_eq(player.player_id, 5)
    assert_eq(player.position, Vector2(100.0, 200.0))


func test_apply_input_sets_velocity():
    var player = PlayerEntityScene.instantiate()
    add_child_autofree(player)
    player.initialize(1, Vector2.ZERO)
    player.apply_input(Vector2(1.0, 0.0))
    assert_eq(player.velocity, Vector2(player.SPEED, 0.0))


func test_apply_input_normalizes_diagonal():
    var player = PlayerEntityScene.instantiate()
    add_child_autofree(player)
    player.initialize(1, Vector2.ZERO)
    player.apply_input(Vector2(1.0, 1.0))
    var expected_speed = player.SPEED
    # Diagonal should be normalized, so magnitude equals SPEED
    assert_almost_eq(player.velocity.length(), expected_speed, 0.01)


func test_apply_zero_input_stops():
    var player = PlayerEntityScene.instantiate()
    add_child_autofree(player)
    player.initialize(1, Vector2.ZERO)
    player.apply_input(Vector2(1.0, 0.0))
    player.apply_input(Vector2.ZERO)
    assert_eq(player.velocity, Vector2.ZERO)


func test_to_snapshot_data():
    var player = PlayerEntityScene.instantiate()
    add_child_autofree(player)
    player.initialize(3, Vector2(50.0, 75.0))
    player.apply_input(Vector2(1.0, 0.0))
    var data = player.to_snapshot_data()
    assert_eq(data["entity_id"], 3)
    assert_eq(data["position"], Vector2(50.0, 75.0))
    assert_eq(data["flags"], MessageTypes.EntityFlags.MOVING)


func test_to_snapshot_data_not_moving():
    var player = PlayerEntityScene.instantiate()
    add_child_autofree(player)
    player.initialize(3, Vector2(50.0, 75.0))
    var data = player.to_snapshot_data()
    assert_eq(data["flags"], MessageTypes.EntityFlags.NONE)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All `test_player_entity` tests FAIL.

- [ ] **Step 3: Create player_entity.tscn scene**

Create `godot/simulation/entities/player_entity.tscn`. This is a CharacterBody2D with a CollisionShape2D (small rectangle hitbox). Create it programmatically or via editor. The scene tree:

```
PlayerEntity (CharacterBody2D)
  └── CollisionShape2D (RectangleShape2D, size 12x12)
```

Create using a minimal `.tscn` file. The script reference points to `player_entity.gd`.

- [ ] **Step 4: Implement player_entity.gd**

Create `godot/simulation/entities/player_entity.gd`:
```gdscript
class_name PlayerEntity
extends CharacterBody2D

const SPEED: float = 200.0

var player_id: int = -1
var last_processed_input_seq: int = 0


func initialize(id: int, spawn_position: Vector2) -> void:
    player_id = id
    position = spawn_position


func apply_input(direction: Vector2) -> void:
    if direction.length_squared() > 0.0:
        velocity = direction.normalized() * SPEED
    else:
        velocity = Vector2.ZERO


func tick() -> void:
    move_and_slide()


func to_snapshot_data() -> Dictionary:
    var flags = MessageTypes.EntityFlags.NONE
    if velocity.length_squared() > 0.0:
        flags = MessageTypes.EntityFlags.MOVING
    return {
        "entity_id": player_id,
        "position": position,
        "flags": flags,
    }
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All `test_player_entity` tests PASS.

- [ ] **Step 6: Commit**

```bash
git add simulation/entities/player_entity.gd simulation/entities/player_entity.tscn tests/entities/test_player_entity.gd
git commit -m "Add PlayerEntity with CharacterBody2D physics and snapshot serialization"
```

---

## Task 7: Movement System

**Files:**
- Create: `godot/simulation/systems/movement_system.gd`
- Create: `godot/tests/systems/test_movement_system.gd`

Processes queued inputs for all players and ticks their physics. Keeps movement logic centralized and out of the entity and network code.

- [ ] **Step 1: Write failing tests**

Create `godot/tests/systems/test_movement_system.gd`:
```gdscript
extends GutTest

var MovementSystem = preload("res://simulation/systems/movement_system.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")

var _system: MovementSystem
var _player: PlayerEntity


func before_each():
    _system = MovementSystem.new()
    add_child_autofree(_system)
    _player = PlayerEntityScene.instantiate()
    add_child_autofree(_player)
    _player.initialize(1, Vector2(100.0, 100.0))
    _system.register_player(_player)


func test_process_inputs_applies_direction():
    var inputs = [
        {"input_seq": 1, "direction": Vector2(1.0, 0.0), "tick": 10},
    ]
    _system.process_inputs_for_player(1, inputs)
    assert_eq(_player.velocity, Vector2(PlayerEntity.SPEED, 0.0))


func test_process_multiple_inputs_applies_last():
    var inputs = [
        {"input_seq": 1, "direction": Vector2(1.0, 0.0), "tick": 10},
        {"input_seq": 2, "direction": Vector2(0.0, -1.0), "tick": 10},
    ]
    _system.process_inputs_for_player(1, inputs)
    # After processing both, velocity should reflect the last input
    assert_eq(_player.velocity, Vector2(0.0, -PlayerEntity.SPEED))


func test_process_empty_inputs_keeps_last_velocity():
    _player.apply_input(Vector2(1.0, 0.0))
    _system.process_inputs_for_player(1, [])
    assert_eq(_player.velocity, Vector2(PlayerEntity.SPEED, 0.0))


func test_tick_all_calls_move_and_slide():
    _player.apply_input(Vector2(1.0, 0.0))
    var pos_before = _player.position
    _system.tick_all()
    # After move_and_slide, position should have changed (no collision in test)
    assert_ne(_player.position, pos_before, "Position should change after tick")


func test_register_and_unregister_player():
    assert_true(_system.has_player(1))
    _system.unregister_player(1)
    assert_false(_system.has_player(1))


func test_updates_last_processed_seq():
    var inputs = [
        {"input_seq": 5, "direction": Vector2(1.0, 0.0), "tick": 10},
        {"input_seq": 7, "direction": Vector2(0.0, 1.0), "tick": 10},
    ]
    _system.process_inputs_for_player(1, inputs)
    assert_eq(_player.last_processed_input_seq, 7)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All `test_movement_system` tests FAIL.

- [ ] **Step 3: Implement movement_system.gd**

Create `godot/simulation/systems/movement_system.gd`:
```gdscript
class_name MovementSystem
extends Node

# player_id -> PlayerEntity
var _players: Dictionary = {}


func register_player(player: PlayerEntity) -> void:
    _players[player.player_id] = player


func unregister_player(player_id: int) -> void:
    _players.erase(player_id)


func has_player(player_id: int) -> bool:
    return _players.has(player_id)


func get_player(player_id: int) -> PlayerEntity:
    return _players.get(player_id)


func process_inputs_for_player(player_id: int, inputs: Array) -> void:
    if not _players.has(player_id):
        return
    var player: PlayerEntity = _players[player_id]
    for input in inputs:
        player.apply_input(input["direction"])
        if input["input_seq"] > player.last_processed_input_seq:
            player.last_processed_input_seq = input["input_seq"]


func tick_all() -> void:
    for player_id in _players:
        _players[player_id].tick()
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All `test_movement_system` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add simulation/systems/movement_system.gd tests/systems/test_movement_system.gd
git commit -m "Add MovementSystem to process player inputs and tick physics"
```

---

## Task 8: Net Server

**Files:**
- Create: `godot/simulation/network/net_server.gd`

WebSocket server with the 20Hz tick loop, player management, connection security, and snapshot building. This is the largest single file — it orchestrates everything server-side.

- [ ] **Step 1: Add connection signals to EventBus**

Add to `godot/simulation/event_bus.gd`:
```gdscript
# Network
signal player_connected(event: Dictionary)
signal player_disconnected(event: Dictionary)
```

- [ ] **Step 2: Implement net_server.gd**

Create `godot/simulation/network/net_server.gd`:
```gdscript
class_name NetServer
extends Node

@export var port: int = 9050

var _tcp_server := TCPServer.new()
# peer_id -> WebSocketPeer
var _peers: Dictionary = {}
# peer_id -> player_id
var _peer_to_player: Dictionary = {}
# player_id -> peer_id
var _player_to_peer: Dictionary = {}
# ip -> Array of connection timestamps (for rate limiting)
var _connection_attempts: Dictionary = {}

var _movement_system: MovementSystem
var _input_buffer := InputBuffer.new()
var _player_entities: Dictionary = {}  # player_id -> PlayerEntity

# Snapshot baselines: player_id -> Snapshot (last ACK'd)
var _baselines: Dictionary = {}

var _tick: int = 0
var _tick_timer: float = 0.0
var _next_player_id: int = 1

const MAX_CONNECTIONS_PER_IP_PER_MINUTE = 10


func _ready():
    _movement_system = MovementSystem.new()
    add_child(_movement_system)

    var err = _tcp_server.listen(port)
    if err == OK:
        print("Server listening on port %d" % port)
    else:
        push_error("Failed to listen on port %d: %s" % [port, error_string(err)])
        set_process(false)
        return


func _process(delta: float):
    _accept_connections()
    _poll_peers()
    _tick_timer += delta
    while _tick_timer >= MessageTypes.TICK_INTERVAL_MS / 1000.0:
        _tick_timer -= MessageTypes.TICK_INTERVAL_MS / 1000.0
        _server_tick()


func _accept_connections():
    while _tcp_server.is_connection_available():
        var tcp_peer = _tcp_server.take_connection()
        var ip = tcp_peer.get_connected_host()

        if not _rate_limit_ok(ip):
            tcp_peer.disconnect_from_host()
            print("Rate limited connection from %s" % ip)
            continue

        if _peers.size() >= MessageTypes.MAX_PLAYERS:
            tcp_peer.disconnect_from_host()
            print("Rejected connection: server full")
            continue

        var ws = WebSocketPeer.new()
        ws.accept_stream(tcp_peer)

        var player_id = _next_player_id
        _next_player_id += 1
        var peer_id = player_id  # 1:1 mapping, simplest approach

        _peers[peer_id] = ws
        _peer_to_player[peer_id] = player_id
        _player_to_peer[player_id] = peer_id

        print("Player %d connected from %s" % [player_id, ip])


func _rate_limit_ok(ip: String) -> bool:
    var now = Time.get_ticks_msec()
    var cutoff = now - 60_000  # 1 minute window
    if not _connection_attempts.has(ip):
        _connection_attempts[ip] = []
    # Prune old entries
    _connection_attempts[ip] = _connection_attempts[ip].filter(func(t): return t > cutoff)
    if _connection_attempts[ip].size() >= MAX_CONNECTIONS_PER_IP_PER_MINUTE:
        return false
    _connection_attempts[ip].append(now)
    return true


func _poll_peers():
    for peer_id in _peers.keys():
        var ws: WebSocketPeer = _peers[peer_id]
        ws.poll()

        var state = ws.get_ready_state()
        if state == WebSocketPeer.STATE_OPEN:
            # Finish handshake: spawn player if not yet spawned
            if not _player_entities.has(_peer_to_player[peer_id]):
                _on_peer_connected(peer_id)

            while ws.get_available_packet_count():
                var packet = ws.get_packet()
                if ws.was_string_packet():
                    # JSON messages from client (none expected in this step, ignore)
                    pass
                else:
                    _handle_binary_message(peer_id, packet)

        elif state == WebSocketPeer.STATE_CLOSED:
            _on_peer_disconnected(peer_id)


func _on_peer_connected(peer_id: int):
    var player_id = _peer_to_player[peer_id]
    var ws: WebSocketPeer = _peers[peer_id]

    # Spawn player entity
    var player_scene = preload("res://simulation/entities/player_entity.tscn")
    var player = player_scene.instantiate()
    player.initialize(player_id, MessageTypes.SPAWN_POSITION)
    add_child(player)
    _player_entities[player_id] = player
    _movement_system.register_player(player)

    # Send handshake (JSON)
    var handshake = NetMessage.encode_json({
        "type": MessageTypes.JSON.HANDSHAKE,
        "server_tick": _tick,
        "player_id": player_id,
        "world_seed": RNG._rng.seed,
    })
    ws.send_text(handshake)

    # Send full snapshot
    var snap = _build_current_snapshot()
    var full_msg = {
        "type": MessageTypes.Binary.FULL_SNAPSHOT,
        "tick": _tick,
        "entities": snap.to_entity_array(),
    }
    ws.send(NetMessage.encode(full_msg))

    # Set baseline for delta compression
    _baselines[player_id] = snap

    # Notify other clients
    var join_msg = NetMessage.encode_json({
        "type": MessageTypes.JSON.PLAYER_JOINED,
        "player_id": player_id,
        "spawn_position": {"x": MessageTypes.SPAWN_POSITION.x, "y": MessageTypes.SPAWN_POSITION.y},
    })
    for other_peer_id in _peers:
        if other_peer_id != peer_id:
            var other_ws: WebSocketPeer = _peers[other_peer_id]
            if other_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
                other_ws.send_text(join_msg)

    EventBus.player_connected.emit({
        "player_id": player_id,
        "position": MessageTypes.SPAWN_POSITION,
    })
    print("Player %d spawned" % player_id)


func _on_peer_disconnected(peer_id: int):
    if not _peer_to_player.has(peer_id):
        _peers.erase(peer_id)
        return

    var player_id = _peer_to_player[peer_id]

    # Clean up player entity
    if _player_entities.has(player_id):
        _movement_system.unregister_player(player_id)
        _player_entities[player_id].queue_free()
        _player_entities.erase(player_id)

    _input_buffer.remove_player(player_id)
    _baselines.erase(player_id)
    _player_to_peer.erase(player_id)
    _peer_to_player.erase(peer_id)
    _peers.erase(peer_id)

    # Notify other clients
    var leave_msg = NetMessage.encode_json({
        "type": MessageTypes.JSON.PLAYER_LEFT,
        "player_id": player_id,
    })
    for other_peer_id in _peers:
        var ws: WebSocketPeer = _peers[other_peer_id]
        if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
            ws.send_text(leave_msg)

    EventBus.player_disconnected.emit({"player_id": player_id})
    print("Player %d disconnected" % player_id)


func _handle_binary_message(peer_id: int, bytes: PackedByteArray):
    var msg = NetMessage.decode_binary(bytes)
    if msg == null:
        return  # Malformed — silently drop

    var player_id = _peer_to_player.get(peer_id, -1)
    if player_id == -1:
        return  # Unknown connection — ignore

    match msg["type"]:
        MessageTypes.Binary.PLAYER_INPUT:
            _input_buffer.add_input(player_id, msg)
        MessageTypes.Binary.SNAPSHOT_ACK:
            _handle_ack(player_id, msg)


func _handle_ack(player_id: int, msg: Dictionary):
    var ack_tick: int = msg["tick"]
    # Update baseline to the snapshot at ack_tick
    # For simplicity, we rebuild from current; in production we'd cache snapshots
    # The baseline is updated at send time — ACK just confirms we can use the latest sent
    pass  # Baseline updated at send time in _server_tick


func _server_tick():
    _tick += 1

    # Phase 1-2: Process queued inputs for each player
    for player_id in _player_entities:
        var inputs = _input_buffer.drain_inputs_for_player(player_id)
        _movement_system.process_inputs_for_player(player_id, inputs)

    # Phase 3: Tick physics
    _movement_system.tick_all()

    # Phase 4-5: Build and send snapshots
    var current_snap = _build_current_snapshot()

    for player_id in _player_to_peer:
        var peer_id = _player_to_peer[player_id]
        var ws: WebSocketPeer = _peers.get(peer_id)
        if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
            continue

        var player: PlayerEntity = _player_entities.get(player_id)
        var last_seq = player.last_processed_input_seq if player else 0

        if not _baselines.has(player_id):
            # No baseline — send full snapshot
            var full_msg = {
                "type": MessageTypes.Binary.FULL_SNAPSHOT,
                "tick": _tick,
                "entities": current_snap.to_entity_array(),
            }
            ws.send(NetMessage.encode(full_msg))
            _baselines[player_id] = current_snap.duplicate_snapshot()
        else:
            var baseline = _baselines[player_id]
            # Check ACK timeout
            if _tick - baseline.tick > MessageTypes.ACK_TIMEOUT_TICKS:
                var full_msg = {
                    "type": MessageTypes.Binary.FULL_SNAPSHOT,
                    "tick": _tick,
                    "entities": current_snap.to_entity_array(),
                }
                ws.send(NetMessage.encode(full_msg))
                _baselines[player_id] = current_snap.duplicate_snapshot()
            else:
                var delta = Snapshot.diff(baseline, current_snap)
                if delta.size() > 0:
                    var delta_msg = {
                        "type": MessageTypes.Binary.DELTA_SNAPSHOT,
                        "tick": _tick,
                        "entities": delta,
                    }
                    ws.send(NetMessage.encode(delta_msg))
                # Update baseline to current for next delta
                _baselines[player_id] = current_snap.duplicate_snapshot()


func _build_current_snapshot() -> Snapshot:
    var snap = Snapshot.new()
    snap.tick = _tick
    for player_id in _player_entities:
        var player: PlayerEntity = _player_entities[player_id]
        snap.entities[player_id] = player.to_snapshot_data()
    return snap
```

- [ ] **Step 3: Commit**

```bash
git add simulation/network/net_server.gd simulation/event_bus.gd
git commit -m "Add NetServer with WebSocket listener, tick loop, and delta snapshots"
```

---

## Task 9: Net Client

**Files:**
- Create: `godot/simulation/network/net_client.gd`

WebSocket client with input sending, client-side prediction for the local player, and snapshot interpolation for remote entities.

- [ ] **Step 1: Implement net_client.gd**

Create `godot/simulation/network/net_client.gd`:
```gdscript
class_name NetClient
extends Node

signal connected(player_id: int)
signal disconnected()
signal snapshot_received(tick: int, entities: Array)
signal player_joined(player_id: int, spawn_position: Vector2)
signal player_left(player_id: int)

var _ws := WebSocketPeer.new()
var _connected: bool = false
var _local_player_id: int = -1
var _server_tick: int = 0

# Client-side prediction state
var _input_seq: int = 0
var _pending_inputs: Array = []  # { seq, direction, predicted_position }
var _local_player: PlayerEntity = null

# Interpolation state: two most recent snapshots for remote entities
var _snapshot_prev: Snapshot = null
var _snapshot_curr: Snapshot = null
var _snapshot_time: float = 0.0  # Time since _snapshot_curr arrived

# Visual reconciliation
const BLEND_THRESHOLD: float = 5.0   # pixels — blend if under this
const SNAP_THRESHOLD: float = 50.0   # pixels — snap if over this
const BLEND_SPEED: float = 10.0      # lerp rate per second
var _visual_offset: Vector2 = Vector2.ZERO  # visual correction being blended out

# Input sending timer (match server tick rate)
var _input_timer: float = 0.0


func connect_to_server(address: String, port: int) -> Error:
    var url = "ws://%s:%d" % [address, port]
    var err = _ws.connect_to_url(url)
    if err != OK:
        push_error("Failed to connect to %s: %s" % [url, error_string(err)])
    return err


func _process(delta: float):
    _ws.poll()
    var state = _ws.get_ready_state()

    if state == WebSocketPeer.STATE_OPEN:
        if not _connected:
            _connected = true

        while _ws.get_available_packet_count():
            var packet = _ws.get_packet()
            if _ws.was_string_packet():
                _handle_json_message(packet.get_string_from_utf8())
            else:
                _handle_binary_message(packet)

        # Send input at tick rate
        _input_timer += delta
        var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
        while _input_timer >= tick_interval:
            _input_timer -= tick_interval
            _send_input()

        # Advance interpolation timer
        _snapshot_time += delta

    elif state == WebSocketPeer.STATE_CLOSED and _connected:
        _connected = false
        _local_player_id = -1
        disconnected.emit()


func _handle_json_message(text: String):
    var msg = NetMessage.decode_json(text)
    if msg == null:
        return

    match msg.get("type", ""):
        MessageTypes.JSON.HANDSHAKE:
            _local_player_id = int(msg["player_id"])
            _server_tick = int(msg["server_tick"])
            RNG.seed(int(msg["world_seed"]))
            connected.emit(_local_player_id)

        MessageTypes.JSON.PLAYER_JOINED:
            var pos_dict = msg["spawn_position"]
            var pos = Vector2(float(pos_dict["x"]), float(pos_dict["y"]))
            player_joined.emit(int(msg["player_id"]), pos)

        MessageTypes.JSON.PLAYER_LEFT:
            player_left.emit(int(msg["player_id"]))


func _handle_binary_message(bytes: PackedByteArray):
    var msg = NetMessage.decode_binary(bytes)
    if msg == null:
        return

    match msg["type"]:
        MessageTypes.Binary.FULL_SNAPSHOT:
            _apply_full_snapshot(msg)
        MessageTypes.Binary.DELTA_SNAPSHOT:
            _apply_delta_snapshot(msg)


func _apply_full_snapshot(msg: Dictionary):
    var snap = Snapshot.new()
    snap.tick = msg["tick"]
    for ent in msg["entities"]:
        snap.entities[ent["entity_id"]] = ent
    _snapshot_prev = snap.duplicate_snapshot()
    _snapshot_curr = snap
    _snapshot_time = 0.0
    _server_tick = msg["tick"]

    _reconcile_local_player(snap)
    _send_ack(msg["tick"])
    snapshot_received.emit(snap.tick, msg["entities"])


func _apply_delta_snapshot(msg: Dictionary):
    if _snapshot_curr == null:
        return  # Need a full snapshot first

    _snapshot_prev = _snapshot_curr.duplicate_snapshot()
    _snapshot_curr.apply_delta(msg["tick"], msg["entities"])
    _snapshot_time = 0.0
    _server_tick = msg["tick"]

    _reconcile_local_player(_snapshot_curr)
    _send_ack(msg["tick"])
    snapshot_received.emit(_snapshot_curr.tick, msg["entities"])


func _send_ack(tick: int):
    var msg = {
        "type": MessageTypes.Binary.SNAPSHOT_ACK,
        "tick": tick,
    }
    _ws.send(NetMessage.encode(msg))


# --- Client-Side Prediction ---

func set_local_player(player: PlayerEntity) -> void:
    _local_player = player


func _send_input():
    if _local_player == null or _local_player_id == -1:
        return

    var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

    _input_seq += 1

    # Predict locally
    _local_player.apply_input(direction)
    _local_player.tick()

    # Store prediction for reconciliation
    _pending_inputs.append({
        "seq": _input_seq,
        "direction": direction,
        "predicted_position": _local_player.position,
    })

    # Send to server
    var msg = {
        "type": MessageTypes.Binary.PLAYER_INPUT,
        "tick": _server_tick,
        "direction": direction,
        "input_seq": _input_seq,
    }
    _ws.send(NetMessage.encode(msg))


func _reconcile_local_player(snap: Snapshot):
    if _local_player == null or _local_player_id == -1:
        return
    if not snap.entities.has(_local_player_id):
        return

    var server_data = snap.entities[_local_player_id]
    var server_pos: Vector2 = server_data["position"]

    # Find the last processed seq from the server
    # We infer this from pruning: remove predictions the server has processed
    # For now, prune all predictions — server snapshot is authoritative
    # In a more advanced version, server sends last_processed_seq per player

    # Discard processed predictions
    _pending_inputs.clear()

    # Calculate correction
    var correction = server_pos - _local_player.position
    var correction_dist = correction.length()

    if correction_dist < 0.01:
        _visual_offset = Vector2.ZERO
    elif correction_dist < SNAP_THRESHOLD:
        # Blend: snap logical position, accumulate visual offset to blend out
        _visual_offset += _local_player.position - server_pos
        _local_player.position = server_pos
    else:
        # Large divergence: snap everything
        _local_player.position = server_pos
        _visual_offset = Vector2.ZERO


# --- Interpolation for Remote Entities ---

func get_interpolated_position(entity_id: int) -> Variant:
    if entity_id == _local_player_id:
        return null  # Local player uses prediction, not interpolation

    if _snapshot_prev == null or _snapshot_curr == null:
        return null

    if not _snapshot_curr.entities.has(entity_id):
        return null

    var curr_pos: Vector2 = _snapshot_curr.entities[entity_id]["position"]

    if not _snapshot_prev.entities.has(entity_id):
        return curr_pos  # New entity, no interpolation yet

    var prev_pos: Vector2 = _snapshot_prev.entities[entity_id]["position"]

    var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
    var t = clampf(_snapshot_time / tick_interval, 0.0, 1.0)
    return prev_pos.lerp(curr_pos, t)


func get_visual_offset() -> Vector2:
    return _visual_offset


func blend_visual_offset(delta: float) -> void:
    _visual_offset = _visual_offset.lerp(Vector2.ZERO, BLEND_SPEED * delta)
    if _visual_offset.length() < 0.1:
        _visual_offset = Vector2.ZERO


func is_connected() -> bool:
    return _connected


func get_local_player_id() -> int:
    return _local_player_id
```

- [ ] **Step 2: Add input actions to project.godot**

Add to `godot/project.godot` under `[input]`:
```ini
[input]

move_left={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":97,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194319,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_right={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":100,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194321,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_up={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":119,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194320,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_down={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":115,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194322,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

This maps WASD + arrow keys to `move_left`, `move_right`, `move_up`, `move_down`.

- [ ] **Step 3: Commit**

```bash
git add simulation/network/net_client.gd project.godot
git commit -m "Add NetClient with prediction, reconciliation, and snapshot interpolation"
```

---

## Task 10: View Layer — Player View and World View

**Files:**
- Create: `godot/view/world/player_view.gd`
- Create: `godot/view/world/player_view.tscn`
- Create: `godot/view/world/world_view.gd`
- Create: `godot/view/world/world_view.tscn`

Visual representations. player_view follows a player (local or remote). world_view holds the TileMap and manages player_view instances.

- [ ] **Step 1: Create player_view.tscn and script**

Scene tree for `godot/view/world/player_view.tscn`:
```
PlayerView (Node2D)
  └── Sprite2D (16x16 colored rectangle placeholder)
```

Create `godot/view/world/player_view.gd`:
```gdscript
extends Node2D

var player_id: int = -1
var is_local: bool = false
var _target_position: Vector2 = Vector2.ZERO


func initialize(id: int, spawn_pos: Vector2, local: bool) -> void:
    player_id = id
    is_local = local
    position = spawn_pos
    _target_position = spawn_pos
    # Color local player differently
    var sprite = $Sprite2D
    if local:
        sprite.modulate = Color(0.3, 0.8, 1.0)  # Blue for local
    else:
        sprite.modulate = Color(1.0, 0.4, 0.3)  # Red for remote


func update_position(new_pos: Vector2) -> void:
    _target_position = new_pos


func _process(delta: float):
    if is_local:
        # Local player: view follows the entity directly
        # Visual offset blending is handled by the client net code
        position = _target_position
    else:
        # Remote player: smooth toward target (interpolated position)
        position = _target_position
```

- [ ] **Step 2: Create the placeholder sprite**

The `Sprite2D` in `player_view.tscn` uses a simple 16x16 white texture (create programmatically or use a PlaceholderTexture2D). Set the texture in the scene file. Alternatively, use a `ColorRect` child instead of `Sprite2D`:

Replace `Sprite2D` with this approach in `player_view.gd` `_ready`:
```gdscript
func _ready():
    # Create a simple colored rectangle as placeholder
    var rect = ColorRect.new()
    rect.size = Vector2(16, 16)
    rect.position = Vector2(-8, -8)  # Center it
    rect.name = "Visual"
    add_child(rect)

func initialize(id: int, spawn_pos: Vector2, local: bool) -> void:
    player_id = id
    is_local = local
    position = spawn_pos
    _target_position = spawn_pos
    var rect = $Visual
    if local:
        rect.color = Color(0.3, 0.8, 1.0)
    else:
        rect.color = Color(1.0, 0.4, 0.3)
```

Updated full `godot/view/world/player_view.gd`:
```gdscript
extends Node2D

var player_id: int = -1
var is_local: bool = false
var _target_position: Vector2 = Vector2.ZERO


func _ready():
    var rect = ColorRect.new()
    rect.size = Vector2(16, 16)
    rect.position = Vector2(-8, -8)
    rect.name = "Visual"
    add_child(rect)


func initialize(id: int, spawn_pos: Vector2, local: bool) -> void:
    player_id = id
    is_local = local
    position = spawn_pos
    _target_position = spawn_pos
    var rect = $Visual
    if local:
        rect.color = Color(0.3, 0.8, 1.0)
    else:
        rect.color = Color(1.0, 0.4, 0.3)


func update_position(new_pos: Vector2) -> void:
    _target_position = new_pos


func _process(_delta: float):
    position = _target_position
```

Scene file `godot/view/world/player_view.tscn` is minimal — just a Node2D with the script attached. The ColorRect is created in `_ready`.

- [ ] **Step 3: Create world_view.tscn and script**

`godot/view/world/world_view.gd` manages the TileMap and player view instances:
```gdscript
extends Node2D

var PlayerViewScene: PackedScene = preload("res://view/world/player_view.tscn")

var _player_views: Dictionary = {}  # player_id -> PlayerView node
var _net_client: NetClient = null


func initialize(net_client: NetClient) -> void:
    _net_client = net_client
    _net_client.connected.connect(_on_connected)
    _net_client.disconnected.connect(_on_disconnected)
    _net_client.player_joined.connect(_on_player_joined)
    _net_client.player_left.connect(_on_player_left)
    _net_client.snapshot_received.connect(_on_snapshot)


func _on_connected(player_id: int):
    # Local player view will be created when first snapshot arrives
    pass


func _on_disconnected():
    for view in _player_views.values():
        view.queue_free()
    _player_views.clear()


func _on_player_joined(player_id: int, spawn_position: Vector2):
    _add_player_view(player_id, spawn_position, false)


func _on_player_left(player_id: int):
    _remove_player_view(player_id)


func _on_snapshot(_tick: int, entities: Array):
    for ent in entities:
        var eid: int = ent["entity_id"]

        if ent.get("flags", 0) & MessageTypes.EntityFlags.REMOVED:
            _remove_player_view(eid)
            continue

        # Create view if it doesn't exist yet
        if not _player_views.has(eid):
            var is_local = (eid == _net_client.get_local_player_id())
            _add_player_view(eid, ent["position"], is_local)


func _process(delta: float):
    if _net_client == null:
        return

    # Update remote player positions via interpolation
    for player_id in _player_views:
        var view = _player_views[player_id]
        if view.is_local:
            # Local player: follow entity position + visual offset
            if _net_client._local_player != null:
                var offset = _net_client.get_visual_offset()
                view.update_position(_net_client._local_player.position + offset)
                _net_client.blend_visual_offset(delta)
        else:
            var interp_pos = _net_client.get_interpolated_position(player_id)
            if interp_pos != null:
                view.update_position(interp_pos)


func _add_player_view(player_id: int, pos: Vector2, is_local: bool):
    if _player_views.has(player_id):
        return
    var view = PlayerViewScene.instantiate()
    add_child(view)
    view.initialize(player_id, pos, is_local)
    _player_views[player_id] = view


func _remove_player_view(player_id: int):
    if _player_views.has(player_id):
        _player_views[player_id].queue_free()
        _player_views.erase(player_id)
```

Scene `godot/view/world/world_view.tscn`:
```
WorldView (Node2D) [script: world_view.gd]
  └── TileMapLayer (16x16 tile size, placeholder tiles: grey floor + dark wall border)
```

The TileMapLayer uses a simple tileset with two tiles: floor (grey) and wall (dark). Create a minimal tileset in the editor or as a `.tres` resource. The TileMap should be roughly 30x20 tiles with walls on the border.

- [ ] **Step 4: Commit**

```bash
git add view/world/player_view.gd view/world/player_view.tscn view/world/world_view.gd view/world/world_view.tscn
git commit -m "Add PlayerView and WorldView for visual rendering and interpolation"
```

---

## Task 11: Connection UI

**Files:**
- Create: `godot/view/ui/connection_ui.gd`
- Create: `godot/view/ui/connection_ui.tscn`

Minimal UI: server address field, connect button, status label.

- [ ] **Step 1: Create connection_ui.tscn and script**

Scene tree for `godot/view/ui/connection_ui.tscn`:
```
ConnectionUI (CanvasLayer)
  └── VBoxContainer (anchored center)
        ├── Label ("Hexvael")
        ├── HBoxContainer
        │     ├── LineEdit (name: AddressInput, placeholder: "localhost", text: "localhost")
        │     └── LineEdit (name: PortInput, placeholder: "9050", text: "9050")
        ├── Button (name: ConnectButton, text: "Connect")
        └── Label (name: StatusLabel, text: "Disconnected")
```

Create `godot/view/ui/connection_ui.gd`:
```gdscript
extends CanvasLayer

signal connect_requested(address: String, port: int)

@onready var _address_input: LineEdit = %AddressInput
@onready var _port_input: LineEdit = %PortInput
@onready var _connect_button: Button = %ConnectButton
@onready var _status_label: Label = %StatusLabel


func _ready():
    _connect_button.pressed.connect(_on_connect_pressed)


func _on_connect_pressed():
    var address = _address_input.text.strip_edges()
    var port = int(_port_input.text.strip_edges())
    if address.is_empty():
        address = "localhost"
    if port <= 0:
        port = 9050
    _connect_button.disabled = true
    _status_label.text = "Connecting..."
    connect_requested.emit(address, port)


func set_status(text: String) -> void:
    _status_label.text = text


func set_connected() -> void:
    _status_label.text = "Connected"
    visible = false  # Hide UI once connected


func set_disconnected() -> void:
    _status_label.text = "Disconnected"
    _connect_button.disabled = false
    visible = true
```

- [ ] **Step 2: Commit**

```bash
git add view/ui/connection_ui.gd view/ui/connection_ui.tscn
git commit -m "Add connection UI with address input and status display"
```

---

## Task 12: Server Scene

**Files:**
- Create: `godot/server.tscn`
- Create: `godot/server_main.gd`

The headless server entry point. Parses CLI args, sets up the NetServer and collision world.

- [ ] **Step 1: Create server_main.gd**

Create `godot/server_main.gd`:
```gdscript
extends Node

var _net_server: NetServer


func _ready():
    var port = 9050

    # Parse CLI args
    var args = OS.get_cmdline_user_args()
    for i in range(args.size()):
        if args[i] == "--port" and i + 1 < args.size():
            port = int(args[i + 1])

    # Seed RNG
    RNG.seed(12345)  # Fixed seed for determinism; will be configurable later

    _net_server = NetServer.new()
    _net_server.port = port
    add_child(_net_server)

    print("Hexvael server starting on port %d" % port)
```

- [ ] **Step 2: Create server.tscn**

Scene tree for `godot/server.tscn`:
```
ServerMain (Node) [script: server_main.gd]
  └── StaticBody2D (arena walls — collision only, no visuals)
        ├── CollisionShape2D (top wall)
        ├── CollisionShape2D (bottom wall)
        ├── CollisionShape2D (left wall)
        └── CollisionShape2D (right wall)
```

The arena is 30x20 tiles at 16px = 480x320 pixels. Wall collision shapes are `RectangleShape2D` segments around the border:
- Top: position (240, -4), size (480, 8)
- Bottom: position (240, 324), size (480, 8)
- Left: position (-4, 160), size (8, 320)
- Right: position (484, 160), size (8, 320)

These give the server collision boundaries without any TileMap visuals.

- [ ] **Step 3: Create a launch script for convenience**

Create `run_server.sh` at the project root:
```bash
#!/bin/bash
cd "$(dirname "$0")/godot"
godot --headless --main-scene res://server.tscn -- "$@"
```
Make it executable: `chmod +x run_server.sh`

- [ ] **Step 4: Commit**

```bash
git add server_main.gd server.tscn ../run_server.sh
git commit -m "Add headless server scene with collision arena and CLI arg parsing"
```

---

## Task 13: Client Scene

**Files:**
- Create: `godot/client.tscn`
- Create: `godot/client_main.gd`

The browser/desktop client entry point. Wires up NetClient, WorldView, ConnectionUI, and the local player entity for prediction.

- [ ] **Step 1: Create client_main.gd**

Create `godot/client_main.gd`:
```gdscript
extends Node

var _net_client: NetClient
var _world_view: Node2D
var _connection_ui: CanvasLayer
var _local_player: PlayerEntity = null


func _ready():
    _net_client = $NetClient
    _world_view = $WorldView
    _connection_ui = $ConnectionUI

    _world_view.initialize(_net_client)
    _connection_ui.connect_requested.connect(_on_connect_requested)
    _net_client.connected.connect(_on_connected)
    _net_client.disconnected.connect(_on_disconnected)


func _on_connect_requested(address: String, port: int):
    var err = _net_client.connect_to_server(address, port)
    if err != OK:
        _connection_ui.set_status("Connection failed")


func _on_connected(player_id: int):
    _connection_ui.set_connected()

    # Spawn local player entity for prediction (simulation layer, no visuals)
    var player_scene = preload("res://simulation/entities/player_entity.tscn")
    _local_player = player_scene.instantiate()
    _local_player.initialize(player_id, MessageTypes.SPAWN_POSITION)
    add_child(_local_player)
    _net_client.set_local_player(_local_player)


func _on_disconnected():
    _connection_ui.set_disconnected()
    if _local_player != null:
        _local_player.queue_free()
        _local_player = null
```

- [ ] **Step 2: Create client.tscn**

Scene tree for `godot/client.tscn`:
```
ClientMain (Node) [script: client_main.gd]
  ├── NetClient (Node) [script: res://simulation/network/net_client.gd]
  ├── WorldView (instance of res://view/world/world_view.tscn)
  ├── ConnectionUI (instance of res://view/ui/connection_ui.tscn)
  └── Camera2D (position: 240, 160 — centered on arena)
```

- [ ] **Step 3: Set client.tscn as default scene**

Update `project.godot` to set the run/main_scene:
```ini
[application]

config/name="hexvael"
run/main_scene="res://client.tscn"
```

This way pressing F5 in the editor launches the client.

- [ ] **Step 4: Commit**

```bash
git add client_main.gd client.tscn project.godot
git commit -m "Add client scene with NetClient, WorldView, and ConnectionUI wired up"
```

---

## Task 14: Integration Test — End to End

**Files:**
- Modify: `godot/tests/test_smoke.gd` (replace smoke test with integration verification checklist)

This is a manual integration test. Automated integration testing of WebSocket connections in GUT is complex and fragile — the value is in the manual play test.

- [ ] **Step 1: Verify server starts headless**

From the `godot/` directory:
```bash
godot --headless --main-scene res://server.tscn -- --port 9050
```
Expected: Terminal prints `Hexvael server starting on port 9050` and `Server listening on port 9050`. Process stays running.

- [ ] **Step 2: Verify client connects (desktop)**

In a second terminal, run the editor or a desktop client:
```bash
godot --main-scene res://client.tscn
```
Click "Connect" in the UI.
Expected: Status shows "Connected". A blue rectangle appears at the spawn position. Server terminal prints `Player 1 connected` and `Player 1 spawned`.

- [ ] **Step 3: Verify second client connects and sees first player**

Open a third terminal and launch another client:
```bash
godot --main-scene res://client.tscn
```
Click "Connect".
Expected: Second client sees a blue rectangle (self) and a red rectangle (first player). First client sees its own blue rectangle and a new red rectangle (second player). Server prints `Player 2 connected`.

- [ ] **Step 4: Verify movement syncs**

Move player 1 with WASD. Expected: Player 1's rectangle moves smoothly in their own client. Player 2's client shows player 1's red rectangle moving smoothly (interpolated).

Move player 2 with WASD. Expected: Same behavior in reverse.

- [ ] **Step 5: Verify disconnect cleanup**

Close one client window. Expected: The remaining client sees the disconnected player's rectangle disappear. Server prints `Player N disconnected`.

- [ ] **Step 6: Run all GUT unit tests**

```bash
godot --headless -s addons/gut/gut_cmdline.gd -gdir=res://tests/ -gprefix=test_ -ginclude_subdirs
```
Expected: All unit tests PASS (net_message, input_buffer, snapshot, player_entity, movement_system).

- [ ] **Step 7: Commit — remove smoke test, update devlog**

Replace `godot/tests/test_smoke.gd` contents with:
```gdscript
extends GutTest

func test_smoke():
    assert_true(true, "GUT is operational")
```

Update `DEVLOG.md` to record completion of step 1.

```bash
git add tests/test_smoke.gd ../DEVLOG.md
git commit -m "Complete multiplayer foundation — step 1 of build order"
```

---

## Task 15: Web Export Verification

**Files:**
- Modify: `godot/project.godot` (export presets if needed)

The primary target is browser. Verify the client works as a web export.

- [ ] **Step 1: Add web export preset**

In the Godot editor: Project > Export > Add > Web. Use default settings. The renderer is already `gl_compatibility` which is required for web.

- [ ] **Step 2: Export and test**

Export the project to `godot/export/web/`. Serve it locally:
```bash
cd godot/export/web && python3 -m http.server 8080
```

Open `http://localhost:8080/hexvael.html` in two browser tabs. Connect both to the server (which should still be running headless).

Expected: Same behavior as desktop — two players move and sync. Movement is smooth with interpolation.

- [ ] **Step 3: Commit export preset**

```bash
git add export_presets.cfg
git commit -m "Add web export preset for browser testing"
```
