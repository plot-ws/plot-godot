# Point sampling of interpolated state at an arbitrary past server timestamp —
# the client-side analogue of the server's `ctx.rewindTo`.
#
# Ports interpolation/sampler.ts. Shares the same SnapshotBuffer + lerp +
# wildcard path resolver the live frame loop uses, but is a pure read: it does
# not touch the frame loop or any prediction/correction state.
class_name PlotSampler

# Returns:
#  - a single interpolated value for a plain path,
#  - a Dictionary keyed by resolved leaf path for a `*` wildcard,
#  - null when the buffer is empty or `at_server_ts` is outside the retained
#    horizon [oldest.ts, newest.ts].
static func sample_at(buffer: PlotSnapshotBuffer, path: String, type: String, at_server_ts: float):
    var oldest = buffer.oldest
    var newest = buffer.newest
    if oldest == null or newest == null:
        return null
    # Outside the retained horizon — the live frame loop would clamp here, but
    # a deliberate point sample must not report a clamped endpoint as if it
    # were the value at the requested time.
    if at_server_ts < float(oldest["ts"]) or at_server_ts > float(newest["ts"]):
        return null

    var is_wildcard := path.contains("*")
    var pair = buffer.lookup(at_server_ts)
    if pair == null:
        return {} if is_wildcard else null
    var a: Dictionary = pair["a"]
    var b = pair["b"]

    var out := {}
    if b == null:
        # Single snapshot or exactly on an endpoint — emit resolved a values.
        for leaf in PlotPathResolver.resolve(path, a["state"], a["state"]):
            if not PlotPathResolver.is_missing(leaf["value_a"]):
                out[leaf["path"]] = leaf["value_a"]
        return _collapse(out, path, is_wildcard)

    var a_ts := float(a["ts"])
    var b_ts := float(b["ts"])
    var t := (at_server_ts - a_ts) / (b_ts - a_ts)
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
    return _collapse(out, path, is_wildcard)

static func _collapse(out: Dictionary, path: String, is_wildcard: bool):
    if is_wildcard:
        return out
    return out[path] if out.has(path) else null
