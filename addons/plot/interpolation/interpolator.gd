# Interpolates a single registered path/type against a SnapshotBuffer.
#
# Ports interpolation/interpolator.ts. Resolves the path against the bracketing
# snapshot pair and lerps each leaf by the configured type, clamping t.
class_name PlotInterpolator

var path: String
var type: String
var render_delay: float

func _init(p_path: String, p_type: String, p_render_delay: float = 100.0) -> void:
    path = p_path
    type = p_type
    render_delay = p_render_delay

# Returns a Dictionary { leaf_path: interpolated_value }.
func tick(target_ts: float, buffer: PlotSnapshotBuffer) -> Dictionary:
    var pair = buffer.lookup(target_ts)
    if pair == null:
        return {}
    var a: Dictionary = pair["a"]
    var b = pair["b"]
    var out := {}

    if b == null:
        # Single snapshot or clamped to one end — emit the resolved a values.
        for leaf in PlotPathResolver.resolve(path, a["state"], a["state"]):
            if not PlotPathResolver.is_missing(leaf["value_a"]):
                out[leaf["path"]] = leaf["value_a"]
        return out

    var a_ts := float(a["ts"])
    var b_ts := float(b["ts"])
    var t := (target_ts - a_ts) / (b_ts - a_ts)
    var t_clamped: float = clampf(t, 0.0, 1.0)
    for leaf in PlotPathResolver.resolve(path, a["state"], b["state"]):
        var va = leaf["value_a"]
        var vb = leaf["value_b"]
        var va_missing := PlotPathResolver.is_missing(va)
        var vb_missing := PlotPathResolver.is_missing(vb)
        if va_missing and vb_missing:
            continue
        if va_missing:
            out[leaf["path"]] = vb
            continue
        if vb_missing:
            out[leaf["path"]] = va
            continue
        out[leaf["path"]] = PlotLerp.by_type(type, va, vb, t_clamped)
    return out
