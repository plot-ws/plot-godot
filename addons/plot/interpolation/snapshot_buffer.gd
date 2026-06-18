# Ring-style snapshot buffer with a fixed time horizon.
#
# Ports interpolation/snapshot-buffer.ts. Stores monotonically-timestamped
# state snapshots and evicts old ones beyond the horizon, while keeping a
# left-side anchor so pair lookup is well-defined across the whole range.
class_name PlotSnapshotBuffer

# Each snapshot: { "ts": float, "state": Variant }.
var _snapshots: Array = []
var _horizon_ms: float

func _init(horizon_ms: float) -> void:
    _horizon_ms = horizon_ms

func push(ts: float, state) -> void:
    if not is_finite(ts):
        return
    if _snapshots.size() > 0:
        var last: Dictionary = _snapshots[_snapshots.size() - 1]
        if ts <= float(last["ts"]):
            return
    _snapshots.append({"ts": ts, "state": state})
    var cutoff := ts - _horizon_ms
    # Keep _snapshots[0] as a left-side anchor whenever _snapshots[1] is still
    # stale; drop the head only when the next snapshot is itself within the
    # horizon.
    while _snapshots.size() > 1 and float(_snapshots[1]["ts"]) < cutoff:
        _snapshots.pop_front()

# Returns { "a": Snapshot, "b": Snapshot|null } or null when empty.
func lookup(target_ts: float):
    var n := _snapshots.size()
    if n == 0:
        return null
    if n == 1:
        return {"a": _snapshots[0], "b": null}
    var first: Dictionary = _snapshots[0]
    var last: Dictionary = _snapshots[n - 1]
    if target_ts <= float(first["ts"]):
        return {"a": first, "b": null}
    if target_ts >= float(last["ts"]):
        return {"a": last, "b": null}
    for i in range(n - 1):
        var a: Dictionary = _snapshots[i]
        var b: Dictionary = _snapshots[i + 1]
        if float(a["ts"]) <= target_ts and target_ts < float(b["ts"]):
            return {"a": a, "b": b}
    # Unreachable for any target in (first.ts, last.ts); defensive fallback.
    return {"a": last, "b": null}

var size: int:
    get:
        return _snapshots.size()

var oldest:
    get:
        return _snapshots[0] if _snapshots.size() > 0 else null

var newest:
    get:
        return _snapshots[_snapshots.size() - 1] if _snapshots.size() > 0 else null
