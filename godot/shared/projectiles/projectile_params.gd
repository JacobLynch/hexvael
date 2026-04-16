class_name ProjectileParams
extends Resource

@export var speed: float = 600.0
@export var lifetime: float = 1.5
@export var radius: float = 6.0
@export var spawn_offset: float = 40.0
@export var spawn_grace: float = 0.10
@export var fire_cooldown: float = 0.20
@export var impact_force: float = 0.0

## Movement behavior type — see ProjectileMovement.Type enum
@export var movement_type: int = 0  # ProjectileMovement.Type.STRAIGHT

## Optional: path to visual scene to instantiate (empty = default polygon)
@export var visual_scene: String = ""

## Knockback force applied to enemies on hit. 0 = no knockback.
@export var knockback_force: float = 0.0
## Stagger duration in seconds. Enemy pauses AI during this time.
@export var knockback_stagger: float = 0.0
