# Client-side prediction with server reconciliation.
#
# Ports handler-client/predictor.ts. Engine deviation: instead of running the
# TS handler module, prediction is driven by a caller-supplied predict fn:
#
#     Callable(state: Variant, input: Variant, player: Dictionary) -> Variant
#
# The predict fn must return the next state. State is deep-cloned (duplicate
# true) before every predict-fn call so the fn can mutate freely without
# corrupting authoritative/predicted snapshots.
class_name PlotPredictor
extends RefCounted

# Emitted after every reconcile with the measured drift magnitude.
signal reconciled(drift: float)

var _authoritative = {}
var _predicted = {}
var _queue := PlotInputQueue.new()
var _disabled := false
var _predict_fn: Callable
var _player: Dictionary
var on_reconcile: Callable = Callable()

func _init(predict_fn: Callable, player: Dictionary) -> void:
    _predict_fn = predict_fn
    _player = player

func set_authoritative(state) -> void:
    _authoritative = state
    _predicted = _deep_clone(state)

var predicted_state:
    get:
        return _predicted

var queue: PlotInputQueue:
    get:
        return _queue

var disabled: bool:
    get:
        return _disabled

func apply(entry: Dictionary) -> void:
    if _disabled:
        return
    var next = _run_predict(_predicted, entry["input"])
    if next == null:
        # Predict fn signalled failure (returned null); drop the input.
        return
    _predicted = next
    var overflowed := _queue.push(entry)
    if overflowed and _queue.size >= PlotInputQueue.CAP:
        push_warning("[predictor] input queue overflowed; disabling prediction")
        _disabled = true
        _queue.clear()
        _predicted = _deep_clone(_authoritative)

func reconcile(server_state, last_acked_seq: int) -> void:
    _authoritative = server_state
    _queue.ack_up_to(last_acked_seq)
    var replayed = _deep_clone(server_state)
    var failed := false
    for entry in _queue.pending():
        var next = _run_predict(replayed, entry["input"])
        if next == null:
            failed = true
            break
        replayed = next
    if failed:
        push_warning("[predictor] replay failed; clearing queue")
        _queue.clear()
        replayed = _deep_clone(server_state)
    var drift := _json_diff_magnitude(_predicted, replayed)
    _predicted = replayed
    reconciled.emit(drift)
    if on_reconcile.is_valid():
        on_reconcile.call(drift)

func disable() -> void:
    _disabled = true
    _queue.clear()
    _predicted = _deep_clone(_authoritative)

# Deep-clones state then invokes the predict fn. Returns the next state, or
# null if the fn itself returned null (treated as failure by callers).
func _run_predict(state, input):
    var cloned = _deep_clone(state)
    return _predict_fn.call(cloned, input, _player)

static func _deep_clone(v):
    if v is Dictionary or v is Array:
        return v.duplicate(true)
    return v

# Ports jsonDiffMagnitude from handler-client/predictor.ts.
static func _json_diff_magnitude(a, b) -> float:
    if _same_value(a, b):
        return 0.0
    var a_num := (a is int or a is float)
    var b_num := (b is int or b is float)
    if a_num and b_num:
        return absf(float(a) - float(b))
    if _kind(a) != _kind(b):
        return 1.0
    if a == null or b == null:
        return 1.0
    if not (a is Dictionary or a is Array):
        return 0.0 if _same_value(a, b) else 1.0
    var ao := _as_dict(a)
    var bo := _as_dict(b)
    var keys := {}
    for k in ao.keys():
        keys[k] = true
    for k in bo.keys():
        keys[k] = true
    var total := 0.0
    for k in keys.keys():
        total += _json_diff_magnitude(ao.get(k, null), bo.get(k, null))
    return total

# Coarse type identity mirroring JS `typeof`: number / object / other.
static func _kind(v) -> String:
    if v is int or v is float:
        return "number"
    if v is Dictionary or v is Array:
        return "object"
    if v is bool:
        return "boolean"
    if v is String or v is StringName:
        return "string"
    return "other"

static func _same_value(a, b) -> bool:
    return typeof(a) == typeof(b) and a == b

# Normalizes Dictionary/Array to a Dictionary keyed by index/key so the
# recursive walk treats arrays like keyed objects (as JS does).
static func _as_dict(v) -> Dictionary:
    if v is Dictionary:
        return v
    var d := {}
    var arr: Array = v
    for i in arr.size():
        d[i] = arr[i]
    return d
