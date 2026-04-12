class_name ProjectileSystem
extends Node

const MAX_ACTIVE = 1024

enum DespawnReason {
	ALIVE    = -1,
	LIFETIME = 0,
	WALL     = 1,
	ENEMY    = 2,
	PLAYER   = 3,
	SELF     = 4,
	REJECTED = 5,  # client-only, never broadcast
}

var projectiles: Dictionary = {}         # projectile_id -> ProjectileEntity
var _next_server_id: int = 1
var _walls: Array[Rect2] = []
var _fire_cooldown: Dictionary = {}      # player_id -> seconds remaining
var _current_rtt_ms: int = 0             # local client's RTT estimate for rejection timeout

func set_walls(aabbs: Array[Rect2]) -> void:
	_walls = aabbs

func get_walls() -> Array[Rect2]:
	return _walls
