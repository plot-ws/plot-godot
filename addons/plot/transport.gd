extends RefCounted
class_name PlotTransport

signal message_received(json: String)
signal closed

var _ws: WebSocketPeer

func open(ws_url: String, room_code: String, token: String) -> int:
    _ws = WebSocketPeer.new()
    _ws.set_handshake_headers(PackedStringArray(["X-Plot-Protocol: v1b.0"]))
    var url := "%s?roomCode=%s&token=%s" % [ws_url, room_code.uri_encode(), token.uri_encode()]
    var err := _ws.connect_to_url(url)
    return err

func send(json: String) -> void:
    _ws.send_text(json)

func close() -> void:
    _ws.close()
    closed.emit()

func _poll() -> void:
    _ws.poll()
    while _ws.get_available_packet_count() > 0:
        var pkt := _ws.get_packet().get_string_from_utf8()
        message_received.emit(pkt)
