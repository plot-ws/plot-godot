# Time-decaying correction offset for a single predicted path.
#
# Ports handler-client/correction-track.ts. Records a drift offset at a point
# in time and reads back a decayed offset: scaled by (1 - elapsed/duration),
# zero once elapsed >= duration, and hard-cleared after 1000ms.
#
# Values use the same dict representation as PlotLerp: number is a float;
# vec2/vec3/quat are dicts with x,y[,z[,w]] float keys.
class_name PlotCorrectionTrack
extends RefCounted

var _type: String
var _duration_ms: float
var _value
var _started_at := 0.0
var _has_record := false

func _init(type: String, duration_ms: float) -> void:
    _type = type
    _duration_ms = duration_ms
    _value = _zero(type)

func record(drift, now: float) -> void:
    _value = drift
    _started_at = now
    _has_record = true

func read(now: float):
    if not _has_record:
        return _zero(_type)
    var elapsed := now - _started_at
    if elapsed >= 1000.0:
        _has_record = false
        return _zero(_type)
    if elapsed >= _duration_ms:
        return _zero(_type)
    if elapsed <= 0.0:
        return _value
    var k := 1.0 - elapsed / _duration_ms
    return _scale(_type, _value, k)

static func _zero(type: String):
    match type:
        "number":
            return 0.0
        "vec2":
            return {"x": 0.0, "y": 0.0}
        "vec3":
            return {"x": 0.0, "y": 0.0, "z": 0.0}
        "quat":
            return {"x": 0.0, "y": 0.0, "z": 0.0, "w": 0.0}
    return 0.0

static func _scale(type: String, v, k: float):
    match type:
        "number":
            return float(v) * k
        "vec2":
            return {"x": float(v["x"]) * k, "y": float(v["y"]) * k}
        "vec3":
            return {"x": float(v["x"]) * k, "y": float(v["y"]) * k, "z": float(v["z"]) * k}
        "quat":
            return {
                "x": float(v["x"]) * k,
                "y": float(v["y"]) * k,
                "z": float(v["z"]) * k,
                "w": float(v["w"]) * k,
            }
    return 0.0
