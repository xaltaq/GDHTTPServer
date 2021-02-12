extends Reference

class Request:
	extends Reference

	var peer: StreamPeerTCP

	var method := ""
	var request_path := ""
	var request_query := ""
	var headers := PoolStringArray()
	var request_data := PoolByteArray()

	func _init(stream_peer: StreamPeerTCP) -> void:
		peer = stream_peer

	func append_header(header: String) -> void:
		headers.append(header)

	func append_request_data_byte(b: int) -> void:
		request_data.append(b)

class RequestParser:
	extends Reference

	enum State {
		SUCCESS,
		FAILURE,
		FIRST_LINE_READ,
		FIRST_LINE_EXPECT_NL,
		HEADER_READ,
		HEADER_EXPECT_NL,
		BODY,
	}

	var request: Request

	var state: int = State.FIRST_LINE_READ
	var curr_line := ""
	var content_length := 0

	func _init(the_request: Request) -> void:
		request = the_request

	func fetch() -> bool:
		while true:
			if not request.peer.is_connected_to_host():
				print_debug("Connection lost")
				return false

			var available_bytes := request.peer.get_available_bytes()
			if available_bytes == 0:
				OS.delay_msec(100)
				continue

			var arr := request.peer.get_data(available_bytes)
			if arr[0] != OK:
				print_debug("Failed to get data (error ", arr[0], ")")
				return false
			for b in arr[1]:
				match state:
					State.FIRST_LINE_READ:
						state = _append_to_line(b, state, State.FIRST_LINE_EXPECT_NL)
					State.FIRST_LINE_EXPECT_NL:
						if b != ord('\n'):
							print_debug("Got \\r with no \\n")
							return false
						state = _parse_first_line()
						curr_line = ""
					State.HEADER_READ:
						state = _append_to_line(b, state, State.HEADER_EXPECT_NL)
					State.HEADER_EXPECT_NL:
						if b != ord('\n'):
							print_debug("Got \\r with no \\n")
							return false
						state = _parse_header()
						curr_line = ""
					State.BODY:
						state = _append_to_body(b)
					_:
						push_error("Invalid state " + str(state))
						return false

				if state == State.SUCCESS:
					print_debug("Request parsed successfully")
					return true
				if state == State.FAILURE:
					return false

		push_error("Reached outside of fetch loop")
		return false

	func _append_to_line(b: int, old_state: int, new_state: int) -> int:
		var c := char(b)
		if c == '\r':
			return new_state
		curr_line += c
		return old_state

	func _parse_first_line() -> int:
		var parts := curr_line.split(" ")
		if parts.size() != 3:
			print_debug("Malformed first line")
			return State.FAILURE

		request.method = parts[0]

		var path_and_query = parts[1].split("?", true, 1)
		request.request_path = path_and_query[0]
		if path_and_query.size() == 2:
			request.request_query = path_and_query[1]

		var protocol: String = parts[2]
		if not protocol.begins_with("HTTP/"):
			print_debug("Malformed protocol")
			return State.FAILURE

		return State.HEADER_READ

	func _parse_header() -> int:
		if curr_line == "":
			if content_length:
				return State.BODY
			return State.SUCCESS

		var header_parts := curr_line.split(": ", true, 1)
		if header_parts.size() != 2:
			print_debug("Malformed header")
			return State.FAILURE
		var header_name: String = header_parts[0]
		var header_value: String = header_parts[1]

		if header_name == "Content-Length":
			if content_length != 0:
				print_debug("Content-Length was set again")
				return State.FAILURE
			if not header_value.is_valid_integer():
				print_debug("Content-Length is invalid")
				return State.FAILURE
			content_length = int(header_value)

		request.append_header(curr_line)
		return State.HEADER_READ

	func _append_to_body(b: int) -> int:
		request.append_request_data_byte(b)
		content_length -= 1
		if content_length == 0:
			return State.SUCCESS
		return State.BODY

class Response:
	extends Reference

	var response_code := 200
	var headers := PoolStringArray()
	var body := PoolByteArray()

	func respond(peer: StreamPeerTCP) -> void:
		_put(peer, "HTTP/1.1 %d\r\n" % response_code)

		for header in headers:
			_put(peer, "%s\r\n" % header)

		if body.empty():
			_put(peer, "\r\n")
		else:
			_put(peer, "Content-Length: %d\r\n\r\n" % body.size())
# warning-ignore:return_value_discarded
			peer.put_data(body)

	func _put(peer: StreamPeerTCP, contents: String) -> void:
# warning-ignore:return_value_discarded
		peer.put_data(contents.to_ascii())

var _responder_instance: Object = self
var _responder_function := "_respond"
var _server_thread := Thread.new()
var _server := TCP_Server.new()
var _server_shutdown := false

func set_responder(instance: Object, function: String):
	_responder_instance = instance
	_responder_function = function

func listen(port: int, bind_address := "*") -> int:
	stop()
	var err := _server.listen(port, bind_address)
	if err == OK:
		err = _server_thread.start(self, "_listen_thread")
	return err

func stop() -> void:
	if _server.is_listening():
		_server.stop()
	if _server_thread.is_active():
		_server_shutdown = true
		_server_thread.wait_to_finish()

# Call this function directly to run the server in the main thread
# For debugging purposes only
func _listen_thread(_null) -> void:
	_server_shutdown = false
	_take_connections()

func _take_connections() -> void:
	while not _server_shutdown:
		if not _server.is_connection_available():
			OS.delay_msec(100)
			continue
		var peer := _server.take_connection()
		print_debug("Got peer: ", peer.get_connected_host(), ":", peer.get_connected_port())
		var request := Request.new(peer)
		var request_parser := RequestParser.new(request)
		if request_parser.fetch():
			var response: Response = _responder_instance.call(_responder_function, request)
			response.respond(peer)
		peer.disconnect_from_host()

# If extending this class, you must override this function
func _respond(_request: Request) -> Response:
	push_error("You must call set_responder or override _respond")
	return null
