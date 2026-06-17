extends Node
class_name PlotClient

var app_key: String
var player_id: String
var api_url := "https://api.plot.ws"

func _init(opts: Dictionary) -> void:
    app_key = opts.get("app_key", "")
    player_id = opts.get("player_id", "")
    api_url = opts.get("api_url", api_url)

func join(opts: Dictionary) -> PlotRoom:
    var http := HTTPRequest.new()
    add_child(http)
    var body := JSON.stringify({ "appKey": app_key, "playerId": player_id })
    var err := http.request(
        api_url + "/v1/connect",
        ["Content-Type: application/json"],
        HTTPClient.METHOD_POST,
        body,
    )
    if err != OK:
        push_error("connect failed")
        return null
    var result = await http.request_completed
    var payload = JSON.parse_string(result[3].get_string_from_utf8())
    var room_code: String = opts.get("room_code", "")
    var transport := PlotTransport.new()
    transport.open(payload.wsUrl, room_code, payload.token)
    return PlotRoom.new(player_id, transport)
