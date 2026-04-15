class_name ProjectileEffectParams
extends Resource
## Configuration for projectile visual effects (muzzle flash, impact, trails).
## Each projectile type can have its own effect params resource.

## Scene spawned at player position when projectile fires. Null = no muzzle flash.
@export var muzzle_scene: PackedScene

## Scene spawned at impact point on collision. Null = no impact effect.
@export var impact_scene: PackedScene

## Scene spawned at impact point on lifetime expiry (no collision). Null = no effect.
@export var expire_scene: PackedScene

## Seconds between trail shard spawns while projectile flies. 0 = disabled.
@export var trail_interval: float = 0.0

## Scene to spawn for trail shards. Required if trail_interval > 0.
@export var trail_scene: PackedScene

## Color to flash enemies on hit.
@export var enemy_flash_color: Color = Color(0.8, 0.95, 1.0, 1.0)

## Duration of enemy flash in seconds.
@export var enemy_flash_duration: float = 0.1

## Scene to spawn attached to enemy on hit (e.g., frost crystals). Null = none.
@export var enemy_cling_scene: PackedScene = null
