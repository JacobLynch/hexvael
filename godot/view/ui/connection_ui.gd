extends CanvasLayer

signal connect_requested(address: String, port: int)

@onready var _address_input: LineEdit = %AddressInput
@onready var _port_input: LineEdit = %PortInput
@onready var _connect_button: Button = %ConnectButton
@onready var _status_label: Label = %StatusLabel


func _ready():
	_connect_button.pressed.connect(_on_connect_pressed)


func _on_connect_pressed():
	var address = _address_input.text.strip_edges()
	var port = int(_port_input.text.strip_edges())
	if address.is_empty():
		address = "localhost"
	if port <= 0:
		port = 9050
	_connect_button.disabled = true
	_status_label.text = "Connecting..."
	connect_requested.emit(address, port)


func set_status(text: String) -> void:
	_status_label.text = text


func set_connected() -> void:
	_status_label.text = "Connected"
	visible = false  # Hide UI once connected


func set_disconnected() -> void:
	_status_label.text = "Disconnected"
	_connect_button.disabled = false
	visible = true
