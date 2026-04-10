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
	DODGING = 4,      # Entity is in the DODGING state (for view-side trail trigger)
}

# Binary layout sizes in bytes
class Layout:
	# Snapshot frame header: [msg_type: u8][tick: u32][entity_count: u16]
	const SNAPSHOT_HEADER_SIZE = 7
	# Per-entity: [entity_id:u16][x:f32][y:f32][flags:u8][last_input_seq:u32]
	#             [vx:f32][vy:f32][aim_x:f32][aim_y:f32][state:u8]
	#             [dodge_time_remaining:f32]
	const ENTITY_SIZE = 36
	# Player input: [msg_type:u8][tick:u32][move_x:f32][move_y:f32]
	#               [aim_x:f32][aim_y:f32][dodge_pressed:u8][input_seq:u32]
	const INPUT_SIZE = 26
	# Snapshot ACK: [msg_type: u8][tick: u32]
	const ACK_SIZE = 5

# Limits
const MAX_PLAYERS = 8
const TICK_RATE = 20
const TICK_INTERVAL_MS: float = 1000.0 / TICK_RATE
const ACK_TIMEOUT_SECONDS: float = 3.0
const ACK_TIMEOUT_TICKS: int = int(ACK_TIMEOUT_SECONDS * TICK_RATE)
const SPAWN_POSITION = Vector2(1200.0, 800.0)  # Center of 2400x1600 arena
const ZOMBIE_TIMEOUT_MS: int = 10000  # 10 seconds with no data = disconnect
