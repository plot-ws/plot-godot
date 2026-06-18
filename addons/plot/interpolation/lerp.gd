# Lerp helpers for snapshot interpolation.
#
# Representation: vectors and quaternions are plain Dictionaries with float
# keys ({x,y} / {x,y,z} / {x,y,z,w}). This matches protocol-decoded JSON
# snapshots (JSON has no Vector2/3/Quaternion), so interpolated output stays
# in the same shape the server sent and round-trips cleanly through the
# correction/prediction layers. Callers that want Godot-native types can
# convert with Vector2(d.x, d.y) etc. at the edge.
class_name PlotLerp

static func lerp_number(a: float, b: float, t: float) -> float:
    return a + (b - a) * t

static func lerp_vec2(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
    return {
        "x": float(a["x"]) + (float(b["x"]) - float(a["x"])) * t,
        "y": float(a["y"]) + (float(b["y"]) - float(a["y"])) * t,
    }

static func lerp_vec3(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
    return {
        "x": float(a["x"]) + (float(b["x"]) - float(a["x"])) * t,
        "y": float(a["y"]) + (float(b["y"]) - float(a["y"])) * t,
        "z": float(a["z"]) + (float(b["z"]) - float(a["z"])) * t,
    }

const _DOT_THRESHOLD := 0.9995

static func _normalize_quat(q: Dictionary) -> Dictionary:
    var len_sq := (
        float(q["x"]) * float(q["x"])
        + float(q["y"]) * float(q["y"])
        + float(q["z"]) * float(q["z"])
        + float(q["w"]) * float(q["w"])
    )
    var l := sqrt(len_sq)
    assert(l != 0.0, "cannot normalize a zero quaternion")
    return {
        "x": float(q["x"]) / l,
        "y": float(q["y"]) / l,
        "z": float(q["z"]) / l,
        "w": float(q["w"]) / l,
    }

# Short-path slerp matching the TS reference (interpolation/lerp/quat.ts).
static func lerp_quat(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
    var ax := float(a["x"])
    var ay := float(a["y"])
    var az := float(a["z"])
    var aw := float(a["w"])
    var bx := float(b["x"])
    var by := float(b["y"])
    var bz := float(b["z"])
    var bw := float(b["w"])
    var dot := ax * bx + ay * by + az * bz + aw * bw
    if dot < 0.0:
        dot = -dot
        bx = -bx
        by = -by
        bz = -bz
        bw = -bw
    # Endpoint short-circuits: trig formulas below carry float noise, so we
    # return endpoints exactly. For dot<0 the short-path destination is the
    # negated b (same rotation).
    if t <= 0.0:
        return {"x": ax, "y": ay, "z": az, "w": aw}
    if t >= 1.0:
        return {"x": bx, "y": by, "z": bz, "w": bw}
    if dot > _DOT_THRESHOLD:
        # Linear lerp of two unit quats drifts off the unit sphere; restore.
        return _normalize_quat({
            "x": ax + (bx - ax) * t,
            "y": ay + (by - ay) * t,
            "z": az + (bz - az) * t,
            "w": aw + (bw - aw) * t,
        })
    var theta0 := acos(dot)
    var sin_theta0 := sin(theta0)
    var theta := theta0 * t
    var sin_theta := sin(theta)
    var s0 := cos(theta) - (dot * sin_theta) / sin_theta0
    var s1 := sin_theta / sin_theta0
    return {
        "x": s0 * ax + s1 * bx,
        "y": s0 * ay + s1 * by,
        "z": s0 * az + s1 * bz,
        "w": s0 * aw + s1 * bw,
    }

static func by_type(type: String, a, b, t: float):
    match type:
        "number":
            return lerp_number(float(a), float(b), t)
        "vec2":
            return lerp_vec2(a, b, t)
        "vec3":
            return lerp_vec3(a, b, t)
        "quat":
            return lerp_quat(a, b, t)
    return null
