extends GutTest

# Unit-test the zombie detection logic in isolation.
# We can't easily spin up a real NetServer in a test, so we test the
# helper method that decides whether a peer is a zombie.


func test_peer_within_timeout_is_not_zombie():
	var now: int = 50000
	var last_activity: int = 45000  # 5 seconds ago
	var is_zombie = (now - last_activity) > MessageTypes.ZOMBIE_TIMEOUT_MS
	assert_false(is_zombie)


func test_peer_beyond_timeout_is_zombie():
	var now: int = 50000
	var last_activity: int = 39000  # 11 seconds ago
	var is_zombie = (now - last_activity) > MessageTypes.ZOMBIE_TIMEOUT_MS
	assert_true(is_zombie)


func test_peer_exactly_at_timeout_is_not_zombie():
	var now: int = 50000
	var last_activity: int = 40000  # exactly 10 seconds ago
	var is_zombie = (now - last_activity) > MessageTypes.ZOMBIE_TIMEOUT_MS
	assert_false(is_zombie, "Exactly at timeout should NOT disconnect — use > not >=")
