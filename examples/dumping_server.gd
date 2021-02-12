extends "res://httpserver.gd"

func _respond(request: Request) -> Response:
	var body := PoolByteArray()
	body.append_array(("Method: %s\n" % request.method).to_ascii())
	body.append_array(("Path: %s\n" % request.request_path).to_ascii())
	body.append_array(("Query: %s\n" % request.request_query).to_ascii())
	for header in request.headers:
		body.append_array((header + "\n").to_ascii())
	body.append_array("Body: ".to_ascii())
	body.append_array(request.request_data)

	var response := Response.new()
	response.body = body
	return response
