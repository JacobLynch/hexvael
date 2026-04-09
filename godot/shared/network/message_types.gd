class_name MessageTypes

# Message type IDs — first byte of every binary message
enum Binary {
    FULL_SNAPSHOT = 1,
    DELTA_SNAPSHOT = 2,
    SNAPSHOT_ACK = 3,
    PLAYER_INPUT = 4,
}

# JSON message types — value of the "type" key
class JsonMsg:
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
