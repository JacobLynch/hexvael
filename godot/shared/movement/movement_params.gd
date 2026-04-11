class_name MovementParams
extends Resource

@export var top_speed: float = 200.0
@export var accel: float = 1800.0              # px/sec² — reach top_speed in ~0.11s
@export var friction: float = 18.0             # exponential coefficient, framerate-independent decay
@export var dodge_speed: float = 700.0         # px/sec during dodge → 140px over 0.2s
@export var dodge_duration: float = 0.2        # seconds
@export var dodge_cooldown: float = 0.7        # seconds, measured from dodge start
@export var dodge_iframe_duration: float = 0.2 # v1: matches dodge_duration
