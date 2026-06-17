# AUTO-GENERATED — do not edit. Run `pnpm --filter @plot/protocol codegen`.
# SCHEMA_VERSION = v1b.0
class_name PlotProtocol

const SCHEMA_VERSION := "v1b.0"

enum Channel { STATE, EVENT, CHAT, UNRELIABLE }

class ConnectRequest:
    var app_key: String
    var player_id: String
    var token: String

class ConnectResponse:
    var token: String
    var expires_at: int
    var ws_url: String

class JoinEnvelope:
    var type: String = "join"
    var player_id: String
    var players: Array
    var ts: int

class LeaveEnvelope:
    var type: String = "leave"
    var player_id: String
    var players: Array
    var ts: int

class MessageEnvelope:
    var type: String = "message"
    var from_id: String
    var channel: String = "event"
    var data
    var ts: int

class StateSnapshotEnvelope:
    var type: String = "state-snapshot"
    var state
    var ts: int

class StatePatchEnvelope:
    var type: String = "state-patch"
    var patch
    var ts: int

class ReconnectTokenEnvelope:
    var type: String = "reconnect-token"
    var token: String
    var expires_at: int

class ErrorEnvelope:
    var type: String = "error"
    var code: String
    var message: String

class ClientMessage:
    var type: String = "message"
    var channel: String = "event"
    var data
