extends GutTest

var NetServer = preload("res://simulation/network/net_server.gd")


func test_rejects_non_unit_aim_direction():
	# aim_direction with magnitude 0.5 should be rejected
	var aim = Vector2(0.3, 0.4)  # magnitude = 0.5
	assert_false(_is_valid_aim(aim), "Should reject aim with magnitude != 1")


func test_accepts_unit_aim_direction():
	var aim = Vector2(0.6, 0.8)  # magnitude = 1.0
	assert_true(_is_valid_aim(aim), "Should accept unit aim direction")


func test_accepts_aim_with_float_tolerance():
	# Normalized vectors may have slight floating point error
	var aim = Vector2(0.70710677, 0.70710677)  # sqrt(2)/2, magnitude ~1.0
	assert_true(_is_valid_aim(aim), "Should accept aim within tolerance")


func test_rejects_zero_aim_direction():
	var aim = Vector2.ZERO
	assert_false(_is_valid_aim(aim), "Should reject zero-length aim")


func _is_valid_aim(aim: Vector2) -> bool:
	# Mirror the validation logic we'll add to net_server
	if not (is_finite(aim.x) and is_finite(aim.y)):
		return false
	var mag_sq = aim.length_squared()
	# Must be approximately unit length (0.9 to 1.1 squared = 0.81 to 1.21)
	return mag_sq >= 0.81 and mag_sq <= 1.21
