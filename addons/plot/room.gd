extends RefCounted
class_name PlotRoom

signal message_received(from: String, data: Variant)
signal player_joined(player_id: String)
signal player_left(player_id: String)

# v1f interpolation: emitted each tick_frame with the interpolated leaf map and
# the render-target timestamp it was sampled at.
signal frame_emitted(interpolated: Dictionary, ts: float)

# v1g prediction: emitted after every send_predicted (drift 0) and after every
# reconcile (drift = last measured reconcile drift).
signal predicted(state: Variant, ts: float, drift: float)

var _player_id: String
var _transport: PlotTransport

# Inbound authoritative state and reconciliation bookkeeping.
var current_state = null
var _last_acked_seq := 0

# --- Interpolation state ---
var _buffer := PlotSnapshotBuffer.new(500.0)
var _clock := PlotServerClock.new()
var _interpolators: Array[PlotInterpolator] = []
var _frame_timer: SceneTreeTimer = null
var _frame_loop_active := false
var _frame_loop_interval_ms := 16.0
var _adaptive := {"enabled": false, "gain": 1.5, "max_extra_ms": 200.0}

# --- Prediction state ---
var _predictor: PlotPredictor = null
var _next_seq := 0
var _last_drift := 0.0
# Each track: { "path": String, "type": String, "track": PlotCorrectionTrack,
#               "previous_value": Variant }.
var _predicted_tracks: Array = []
var corrected_state := {}

func _init(player_id: String, transport: PlotTransport) -> void:
    _player_id = player_id
    _transport = transport
    _transport.message_received.connect(_on_inbound)

func send(data: Variant, channel: String = "event") -> void:
    var env := {"type": "message", "channel": channel, "data": data, "clientTs": _now_ms()}
    _transport.send(JSON.stringify(env))

func leave() -> void:
    _transport.close()

# ---------------------------------------------------------------------------
# Interpolation API (ports @plot/client Room interpolation methods)
# ---------------------------------------------------------------------------

func interpolate(path: String, type: String, render_delay: float = 100.0) -> void:
    for existing in _interpolators:
        assert(existing.path != path, "interpolate: path already registered: " + path)
    _interpolators.append(PlotInterpolator.new(path, type, render_delay))

# Adaptive smoothing: when enabled, the render delay grows with measured
# jitter so bursty links buffer more. effective extra = clamp(gain * jitter,
# 0, max_extra_ms), added on top of each interpolator's base render_delay.
func set_adaptive_smoothing(enabled: bool, gain: float = 1.0, max_extra_ms: float = 100.0) -> void:
    _adaptive = {"enabled": enabled, "gain": gain, "max_extra_ms": max_extra_ms}

func adaptive_extra_delay() -> float:
    if not _adaptive["enabled"]:
        return 0.0
    var raw: float = _adaptive["gain"] * _clock.jitter
    return clampf(raw, 0.0, _adaptive["max_extra_ms"])

# `now` must be wall-clock ms (same domain as server `state-*.ts`). Pass -1 to
# use the live wall clock.
func tick_frame(now: float = -1.0) -> void:
    if now < 0.0:
        now = _now_ms()
    if _interpolators.size() > 0:
        var offset := _clock.offset
        var min_delay := INF
        for i in _interpolators:
            min_delay = minf(min_delay, i.render_delay)
        var target := now - offset - min_delay - adaptive_extra_delay()
        var interpolated := {}
        for i in _interpolators:
            interpolated.merge(i.tick(target, _buffer), true)
        frame_emitted.emit(interpolated, target)
    if _predictor != null:
        for t in _predicted_tracks:
            var base = _read_path(_predictor.predicted_state, t["path"])
            var off = t["track"].read(now)
            corrected_state[t["path"]] = _apply_offset(t["type"], base, off)

func start_frame_loop(interval_ms: float = 16.0) -> void:
    stop_frame_loop()
    _frame_loop_interval_ms = interval_ms
    _frame_loop_active = true
    _schedule_frame()

func stop_frame_loop() -> void:
    _frame_loop_active = false
    _frame_timer = null

func _schedule_frame() -> void:
    if not _frame_loop_active:
        return
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        # No SceneTree available (e.g. unit-test context); the loop is a no-op
        # and callers should drive tick_frame() manually.
        _frame_loop_active = false
        return
    _frame_timer = tree.create_timer(_frame_loop_interval_ms / 1000.0)
    _frame_timer.timeout.connect(_on_frame_tick)

func _on_frame_tick() -> void:
    if not _frame_loop_active:
        return
    tick_frame()
    _schedule_frame()

# ---------------------------------------------------------------------------
# Prediction API (ports @plot/client Room prediction methods)
# ---------------------------------------------------------------------------

# Engine deviation from TS attachHandler: predict_fn is a
# Callable(state, input, player) -> state supplied by the game, since engines
# cannot run the TS handler module.
func attach_prediction(initial_state, predict_fn: Callable) -> void:
    assert(_predictor == null, "attach_prediction: prediction already attached")
    var player := {"id": _player_id, "joinedAt": _now_ms()}
    var predictor := PlotPredictor.new(predict_fn, player)
    predictor.on_reconcile = func(drift: float): _last_drift = drift
    var seed = current_state if current_state != null else initial_state
    predictor.set_authoritative(seed)
    _predictor = predictor

var predicted_state:
    get:
        return _predictor.predicted_state if _predictor != null else null

func send_predicted(input: Variant, channel: String = "event") -> void:
    assert(_predictor != null, "send_predicted: attach_prediction must be called first")
    _next_seq += 1
    var seq := _next_seq
    _predictor.apply({"seq": seq, "input": input})
    for t in _predicted_tracks:
        corrected_state[t["path"]] = _read_path(_predictor.predicted_state, t["path"])
    var env := {
        "type": "message",
        "channel": channel,
        "data": input,
        "_seq": seq,
        "clientTs": _now_ms(),
    }
    _transport.send(JSON.stringify(env))
    predicted.emit(_predictor.predicted_state, _now_ms(), 0.0)

func predict(path: String, type: String, correction_ms: float = 100.0) -> void:
    assert(_predictor != null, "predict: attach_prediction must be called first")
    for t in _predicted_tracks:
        assert(t["path"] != path, "predict: path already registered: " + path)
    _predicted_tracks.append({
        "path": path,
        "type": type,
        "track": PlotCorrectionTrack.new(type, correction_ms),
        "previous_value": _read_path(_predictor.predicted_state, path),
    })
    corrected_state[path] = _read_path(_predictor.predicted_state, path)

# ---------------------------------------------------------------------------
# Inbound dispatch
# ---------------------------------------------------------------------------

func _on_inbound(json: String) -> void:
    var env = JSON.parse_string(json)
    if env == null or not (env is Dictionary):
        return
    match env.get("type", ""):
        "message":
            message_received.emit(env.get("from", ""), env.get("data"))
        "join":
            player_joined.emit(env.get("playerId", ""))
        "leave":
            player_left.emit(env.get("playerId", ""))
        "state-snapshot":
            if env.has("lastAckedSeq"):
                _last_acked_seq = int(env["lastAckedSeq"])
            current_state = env.get("state")
            _ingest_snapshot(float(env.get("ts", 0.0)), current_state)
        "state-patch":
            # Engine clients receive already-applied state under "patch" (full
            # document); JSON-Patch composition is resolved server-side for SDKs
            # that do not bundle a patch library.
            if env.has("lastAckedSeq"):
                _last_acked_seq = int(env["lastAckedSeq"])
            current_state = env.get("patch")
            _ingest_snapshot(float(env.get("ts", 0.0)), current_state)

func _ingest_snapshot(ts: float, state) -> void:
    _clock.observe(_now_ms(), ts)
    _buffer.push(ts, state)
    if _predictor != null:
        for t in _predicted_tracks:
            t["previous_value"] = _read_path(_predictor.predicted_state, t["path"])
        _predictor.reconcile(state, _last_acked_seq)
        var now := _now_ms()
        for t in _predicted_tracks:
            var new_value = _read_path(_predictor.predicted_state, t["path"])
            var drift = _compute_drift(t["type"], t["previous_value"], new_value)
            if drift != null:
                t["track"].record(drift, now)
        predicted.emit(_predictor.predicted_state, ts, _last_drift)

# ---------------------------------------------------------------------------
# Path / drift / offset helpers (ports room.ts module-private functions)
# ---------------------------------------------------------------------------

static func _read_path(state, path: String):
    var cur = state
    for seg in path.split("."):
        if not (cur is Dictionary) or not cur.has(seg):
            return null
        cur = cur[seg]
    return cur

static func _compute_drift(type: String, prev, next):
    if prev == null or next == null:
        return null
    match type:
        "number":
            return float(prev) - float(next)
        "vec2":
            return {"x": float(prev["x"]) - float(next["x"]), "y": float(prev["y"]) - float(next["y"])}
        "vec3":
            return {
                "x": float(prev["x"]) - float(next["x"]),
                "y": float(prev["y"]) - float(next["y"]),
                "z": float(prev["z"]) - float(next["z"]),
            }
        "quat":
            return {
                "x": float(prev["x"]) - float(next["x"]),
                "y": float(prev["y"]) - float(next["y"]),
                "z": float(prev["z"]) - float(next["z"]),
                "w": float(prev["w"]) - float(next["w"]),
            }
    return null

static func _apply_offset(type: String, base, off):
    if base == null:
        return null
    match type:
        "number":
            return float(base) + float(off)
        "vec2":
            return {"x": float(base["x"]) + float(off["x"]), "y": float(base["y"]) + float(off["y"])}
        "vec3":
            return {
                "x": float(base["x"]) + float(off["x"]),
                "y": float(base["y"]) + float(off["y"]),
                "z": float(base["z"]) + float(off["z"]),
            }
        "quat":
            return {
                "x": float(base["x"]) + float(off["x"]),
                "y": float(base["y"]) + float(off["y"]),
                "z": float(base["z"]) + float(off["z"]),
                "w": float(base["w"]) + float(off["w"]),
            }
    return base

static func _now_ms() -> float:
    return float(Time.get_unix_time_from_system() * 1000.0)
