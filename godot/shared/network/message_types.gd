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
	ENEMY_HIT            = 8,
	PLAYER_HIT           = 9,
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

# Element tag carried on hit events. Wire-level u8; runtime representation is
# the string (for readability and TCE trigger matching). Add entries here as
# new element strings appear on gear/projectile params.
enum Element {
	UNKNOWN   = 0,
	PHYSICAL  = 1,
	FROST     = 2,
	FIRE      = 3,
	LIGHTNING = 4,
	POISON    = 5,
	ARCANE    = 6,
	HOLY      = 7,
	SHADOW    = 8,
}

const _ELEMENT_STRING_BY_ID: Dictionary = {
	Element.UNKNOWN:   "unknown",
	Element.PHYSICAL:  "physical",
	Element.FROST:     "frost",
	Element.FIRE:      "fire",
	Element.LIGHTNING: "lightning",
	Element.POISON:    "poison",
	Element.ARCANE:    "arcane",
	Element.HOLY:      "holy",
	Element.SHADOW:    "shadow",
}

const _ELEMENT_ID_BY_STRING: Dictionary = {
	"unknown":   Element.UNKNOWN,
	"physical":  Element.PHYSICAL,
	"frost":     Element.FROST,
	"fire":      Element.FIRE,
	"lightning": Element.LIGHTNING,
	"poison":    Element.POISON,
	"arcane":    Element.ARCANE,
	"holy":      Element.HOLY,
	"shadow":    Element.SHADOW,
}

static func element_to_id(element: String) -> int:
	if _ELEMENT_ID_BY_STRING.has(element):
		return _ELEMENT_ID_BY_STRING[element]
	push_warning("MessageTypes.element_to_id: unknown element '%s' — encoded as UNKNOWN" % element)
	return Element.UNKNOWN

static func element_from_id(id: int) -> String:
	return _ELEMENT_STRING_BY_ID.get(id, "unknown")

# Binary layout sizes in bytes
class Layout:
	# Snapshot frame header: [msg_type: u8][tick: u32][entity_count: u16]
	const SNAPSHOT_HEADER_SIZE = 7
	# Per-entity: [entity_id:u16][x:f32][y:f32][flags:u8][last_input_seq:u32]
	#             [vx:f32][vy:f32][aim_x:f32][aim_y:f32][state:u8]
	#             [dodge_time_remaining:f32][collision_count:u8]
	#             [last_collision_normal_x:f32][last_collision_normal_y:f32]
	#             [ghost_timer:f32]
	const ENTITY_SIZE = 49
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
	#                     [tick_age_ms:u8][source_x:f32][source_y:f32]
	const PROJECTILE_SPAWNED_SIZE = 35  # was 27, added 8 bytes for source_position (2 floats)
	# Projectile despawned: [type:u8][projectile_id:u16][reason:u8][x:f32][y:f32][target_entity_id:s16]
	#                       [tick_age_ms:u8]
	const PROJECTILE_DESPAWNED_SIZE = 15
	# Enemy hit: [type:u8][target_entity_id:u16][x:f32][y:f32][damage:u16][remaining_health:u16][max_health:u16]
	#            [source_entity_id:s16][element:u8][chain_depth:u8][projectile_id:s16]
	const ENEMY_HIT_SIZE = 23
	# Player hit: same layout as enemy hit
	const PLAYER_HIT_SIZE = 23

# Limits
const MAX_PLAYERS = 8
const TICK_RATE = 30
const TICK_INTERVAL_MS: float = 1000.0 / TICK_RATE
const ACK_TIMEOUT_SECONDS: float = 3.0
const ACK_TIMEOUT_TICKS: int = int(ACK_TIMEOUT_SECONDS * TICK_RATE)
const SPAWN_POSITION = Vector2(1200.0, 800.0)  # Center of 2400x1600 arena
const ZOMBIE_TIMEOUT_MS: int = 10000  # 10 seconds with no data = disconnect
const TICK_AGE_MAX_MS: int = 255  # Max value for tick_age_ms field (u8)
const MAX_TRACKED_IPS: int = 1000  # Max unique IPs to track for rate limiting
const MAX_INPUTS_PER_TICK: int = 3  # Allow small burst for network jitter
