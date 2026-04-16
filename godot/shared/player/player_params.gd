class_name PlayerParams
extends Resource

## Maximum health. Player enters GHOST state when health reaches 0.
@export var max_health: int = 100

## Time in seconds spent in GHOST state before respawning.
@export var ghost_duration: float = 5.0
