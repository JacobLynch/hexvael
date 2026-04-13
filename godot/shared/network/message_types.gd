class_name MessageTypes

# Message type IDs — first byte of every binary message
enum Binary {
	FULL_SNAPSHOT        = 1,
	DELTA_SNAPSHOT       = 2,
	SNAPSHOT_ACK         = 3,
	PLAYER_INPUT         = 4,
	ENEMY_DIED           = 5,
	PROJECTILE_SPAWNED   = 6,
	PROJECTILE_DESPAWNED = 7,
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

# Enemy-specific state flags used in enemy snapshot data
enum EnemyFlags {
	REMOVED = 255,    # Enemy was removed (delta only)
}

# Action flags bitfield packed into the input packet (1 byte)
enum InputActionFlags {
	NONE  = 0,
	DODGE = 1,  # bit 0
	FIRE  = 2,  # bit 1
}

# Binary layout sizes in bytes
class Layout:
	# Snapshot frame header: [msg_type: u8][tick: u32][entity_count: u16]
	const SNAPSHOT_HEADER_SIZE = 7
	# Per-entity: [entity_id:u16][x:f32][y:f32][flags:u8][last_input_seq:u32]
	#             [vx:f32][vy:f32][aim_x:f32][aim_y:f32][state:u8]
	#             [dodge_time_remaining:f32][collision_count:u8]
	#             [last_collision_normal_x:f32][last_collision_normal_y:f32]
	const ENTITY_SIZE = 45
	# Player input: [msg_type:u8][tick:u32][move_x:f32][move_y:f32]
	#               [aim_x:f32][aim_y:f32][action_flags:u8][input_seq:u32]
	const INPUT_SIZE = 26
	# Snapshot ACK: [msg_type: u8][tick: u32]
	const ACK_SIZE = 5
	# Per-enemy: [entity_id: u16][x: f32][y: f32][state: u8][facing_x: f16][facing_y: f16][spawn_timer: f16]
	const ENEMY_ENTITY_SIZE = 17
	# Enemy died: [type: u8][entity_id: u16][x: f32][y: f32][killer_id: u16]
	const ENEMY_DIED_SIZE = 13
	# Projectile spawned: [type:u8][projectile_id:u16][type_id:u8][owner_player_id:u16]
	#                     [origin_x:f32][origin_y:f32][dir_x:f32][dir_y:f32][input_seq:u32]
	#                     [tick_age_ms:u8]
	const PROJECTILE_SPAWNED_SIZE = 27
	# Projectile despawned: [type:u8][projectile_id:u16][reason:u8][x:f32][y:f32][target_entity_id:s16]
	#                       [tick_age_ms:u8]
	const PROJECTILE_DESPAWNED_SIZE = 15

# Limits
const MAX_PLAYERS = 8
const TICK_RATE = 30
const TICK_INTERVAL_MS: float = 1000.0 / TICK_RATE
const ACK_TIMEOUT_SECONDS: float = 3.0
const ACK_TIMEOUT_TICKS: int = int(ACK_TIMEOUT_SECONDS * TICK_RATE)
const SPAWN_POSITION = Vector2(1200.0, 800.0)  # Center of 2400x1600 arena
const ZOMBIE_TIMEOUT_MS: int = 10000  # 10 seconds with no data = disconnect
const MAX_TRACKED_IPS: int = 1000  # Max unique IPs to track for rate limiting
const MAX_INPUTS_PER_TICK: int = 3  # Allow small burst for network jitter
