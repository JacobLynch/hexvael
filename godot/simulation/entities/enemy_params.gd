class_name EnemyParams
extends Resource

@export var base_speed: float = 180.0
@export var speed_variation: float = 0.15
@export var turn_rate: float = 8.0
@export var separation_radius: float = 32.0
@export var separation_weight: float = 0.8
@export var min_approach_distance: float = 8.0
@export var arrival_radius: float = 20.0
@export var detection_radius: float = 250.0
@export var leash_radius: float = 350.0
@export var hysteresis_distance: float = 80.0
@export var base_spawn_duration: float = 1.2
@export var spawn_duration_variation: float = 0.2
@export var wander_radius: float = 50.0
@export var wander_speed_factor: float = 0.3
@export var mass: float = 1.0  ## Knockback resistance. 1.0 = light, 3.0+ = immune
@export var max_health: int = 50  ## Maximum health. Enemy dies when health reaches 0.
