extends Node

var _net_server: NetServer


func _ready():
	var port = 9050

	# Parse CLI args
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])

	# Seed RNG
	RNG.seed(12345)  # Fixed seed for determinism; will be configurable later

	_net_server = NetServer.new()
	_net_server.port = port
	add_child(_net_server)

	print("Hexvael server starting on port %d" % port)
