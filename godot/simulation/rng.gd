extends Node

var _rng := RandomNumberGenerator.new()

func seed(value: int) -> void:
    _rng.seed = value

func get_seed() -> int:
    return _rng.seed

func next_float() -> float:
    return _rng.randf()

func next_int(from: int, to: int) -> int:
    return _rng.randi_range(from, to)

func next_bool(probability: float = 0.5) -> bool:
    return _rng.randf() < probability