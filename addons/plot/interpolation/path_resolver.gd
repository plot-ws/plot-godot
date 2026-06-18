# Dot-path resolver with a single-level `*` wildcard.
#
# Ports interpolation/path.ts. Resolves a dotted pattern against two states
# (a, b) and returns leaf descriptors. A single `*` segment expands across the
# union of keys present at that level in either state.
#
# Missing values are represented by the MISSING sentinel (distinct from a real
# JSON `null`), mirroring TS `undefined`.
class_name PlotPathResolver

# Unique sentinel for "value not present" (TS undefined).
const MISSING := "__plot_missing__"

# Type-safe check for the sentinel. Comparing an arbitrary Variant (e.g. a
# Dictionary) to a String with `==` throws in GDScript, so callers must use
# this helper rather than `v == MISSING`.
static func is_missing(v) -> bool:
    return (v is String or v is StringName) and v == MISSING

# Each leaf: { "path": String, "value_a": Variant, "value_b": Variant }.

static func _walk(state, segments: Array):
    var cur = state
    for seg in segments:
        if not (cur is Dictionary):
            return MISSING
        if not cur.has(seg):
            return MISSING
        cur = cur[seg]
    return cur

static func resolve(pattern: String, a, b) -> Array:
    var segs := pattern.split(".")
    var wildcard_count := 0
    for s in segs:
        if s == "*":
            wildcard_count += 1
    assert(wildcard_count <= 1, "resolve: multi-wildcard patterns are not supported: " + pattern)

    var star := -1
    for i in segs.size():
        if segs[i] == "*":
            star = i
            break

    if star == -1:
        var seg_arr: Array = Array(segs)
        return [{
            "path": pattern,
            "value_a": _walk(a, seg_arr),
            "value_b": _walk(b, seg_arr),
        }]

    var head: Array = Array(segs).slice(0, star)
    var tail: Array = Array(segs).slice(star + 1)
    var a_parent = _walk(a, head)
    var b_parent = _walk(b, head)

    var keys := {}
    if a_parent is Dictionary:
        for k in a_parent.keys():
            keys[k] = true
    if b_parent is Dictionary:
        for k in b_parent.keys():
            keys[k] = true

    var sorted_keys: Array = keys.keys()
    sorted_keys.sort()

    var out: Array = []
    for k in sorted_keys:
        var child_segs: Array = head.duplicate()
        child_segs.append(k)
        child_segs.append_array(tail)
        var a_has: bool = a_parent is Dictionary and a_parent.has(k)
        var b_has: bool = b_parent is Dictionary and b_parent.has(k)
        var a_child = a_parent[k] if a_has else MISSING
        var b_child = b_parent[k] if b_has else MISSING
        out.append({
            "path": ".".join(PackedStringArray(child_segs.map(func(x): return str(x)))),
            "value_a": MISSING if not a_has else _walk(a_child, tail),
            "value_b": MISSING if not b_has else _walk(b_child, tail),
        })
    return out
