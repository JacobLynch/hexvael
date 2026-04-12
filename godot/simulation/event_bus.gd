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

# Movement
signal player_dodge_started(event: Dictionary)   # entity_id, position, direction
signal player_dodge_ended(event: Dictionary)     # entity_id
signal player_collided(event: Dictionary)        # entity_id, position, normal, velocity
signal player_moved(event: Dictionary)           # entity_id, position, velocity

# Enemies
signal enemy_spawned(event: Dictionary)
signal enemy_state_changed(event: Dictionary)
signal enemy_target_changed(event: Dictionary)

# Projectiles
signal projectile_spawned(event: Dictionary)
signal projectile_despawned(event: Dictionary)
