extends GutTest

# Tests for NetServer per-player RTT tracking.
# Exercises the RTT methods directly without a live WebSocket connection.
# NetServer._ready() may fail to bind port 9050 in test environments — that is
# fine; the RTT dictionaries are initialised at declaration time and the methods
# under test touch no I/O.

var NetServerCls = preload("res://simulation/network/net_server.gd")


func _make_server() -> Node:
	var server = NetServerCls.new()
	add_child_autofree(server)
	return server


func test_get_rtt_ms_defaults_zero():
	var server = _make_server()
	assert_eq(server.get_rtt_ms(42), 0)


func test_record_send_and_ack_produces_positive_rtt():
	var server = _make_server()
	server._record_snapshot_send(42, 100)
	OS.delay_msec(10)
	server._record_snapshot_ack(42, 100)
	var rtt = server.get_rtt_ms(42)
	assert_gt(rtt, 0)
	assert_lt(rtt, 1000)  # tens of ms, not seconds


func test_rolling_average_over_multiple_samples():
	var server = _make_server()
	for tick in [100, 101, 102]:
		server._record_snapshot_send(42, tick)
		OS.delay_msec(5)
		server._record_snapshot_ack(42, tick)
	var rtt = server.get_rtt_ms(42)
	assert_gt(rtt, 0)


func test_per_player_isolation():
	var server = _make_server()
	server._record_snapshot_send(42, 100)
	OS.delay_msec(5)
	server._record_snapshot_ack(42, 100)
	assert_gt(server.get_rtt_ms(42), 0)
	assert_eq(server.get_rtt_ms(99), 0)


func test_ack_without_matching_send_is_safe():
	var server = _make_server()
	server._record_snapshot_ack(42, 999)
	assert_eq(server.get_rtt_ms(42), 0)
