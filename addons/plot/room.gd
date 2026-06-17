extends RefCounted
class_name PlotRoom

signal message_received(from: String, data: Variant)
signal player_joined(player_id: String)
signal player_left(player_id: String)

var _player_id: String
var _transport: PlotTransport

func _init(player_id: String, transport: PlotTransport) -> void:
    _player_id = player_id
    _transport = transport
    _transport.message_received.connect(_on_inbound)

func send(data: Variant, channel: String = "event") -> void:
    var env := { "type": "message", "channel": channel, "data": data }
    _transport.send(JSON.stringify(env))

func leave() -> void:
    _transport.close()

func _on_inbound(json: String) -> void:
    var env = JSON.parse_string(json)
    if env == null:
        return
    if env.type == "message":
        message_received.emit(env.from, env.data)
    elif env.type == "join":
        player_joined.emit(env.playerId)
    elif env.type == "leave":
        player_left.emit(env.playerId)
