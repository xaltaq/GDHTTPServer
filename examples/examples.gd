extends Control

var _curr_server = null

export var _server_buttons: NodePath
export var _server_status: NodePath
export var _port: NodePath
export var _stop_server_button: NodePath

func _ready() -> void:
	_stop_server()

func _start_server(path: String) -> void:
	for child in get_node(_server_buttons).get_children():
		child.disabled = true
	_curr_server = load("res://examples/" + path).new()
	var err = _curr_server.listen(get_node(_port).value)
	if err == OK:
		get_node(_stop_server_button).disabled = false
		get_node(_server_status).text = "Server started"
	else:
		get_node(_server_status).text = "Can't start server - error " + str(err) + ". Try using a different port."
		for child in get_node(_server_buttons).get_children():
			child.disabled = false

func _stop_server() -> void:
	get_node(_stop_server_button).disabled = true
	if _curr_server:
		_curr_server.stop()
		_curr_server = null
	for child in get_node(_server_buttons).get_children():
		child.disabled = false
	get_node(_server_status).text = "Server stopped"
