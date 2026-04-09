extends Node

# Combat
signal enemy_hit(event: Dictionary)
signal enemy_died(event: Dictionary)
signal player_hit(event: Dictionary)
signal player_died(event: Dictionary)

# Effects
signal status_applied(event: Dictionary)
signal surface_created(event: Dictionary)
signal element_interaction(event: Dictionary)

# World
signal room_captured(event: Dictionary)
signal wave_started(event: Dictionary)
signal wave_ended(event: Dictionary)

# Network
signal player_connected(event: Dictionary)
signal player_disconnected(event: Dictionary)