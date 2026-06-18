extends GdUnitTestSuite

# --- InputQueue ---------------------------------------------------------

func test_queue_push_and_ack_drops_acked() -> void:
    var q := PlotInputQueue.new()
    q.push({"seq": 1, "input": "a"})
    q.push({"seq": 2, "input": "b"})
    q.push({"seq": 3, "input": "c"})
    q.ack_up_to(2)
    assert_int(q.size).is_equal(1)
    assert_int(q.pending()[0]["seq"]).is_equal(3)

func test_queue_overflow_flag_and_signal() -> void:
    var q := PlotInputQueue.new()
    var dropped := [-1]
    q.overflowed.connect(func(seq): dropped[0] = seq)
    var last_overflowed := false
    for i in range(PlotInputQueue.CAP + 1):
        last_overflowed = q.push({"seq": i + 1, "input": i})
    assert_bool(last_overflowed).is_true()
    assert_int(q.size).is_equal(PlotInputQueue.CAP)
    assert_int(dropped[0]).is_equal(1)  # oldest seq dropped

func test_queue_clear() -> void:
    var q := PlotInputQueue.new()
    q.push({"seq": 1, "input": "a"})
    q.clear()
    assert_int(q.size).is_equal(0)

# --- CorrectionTrack ----------------------------------------------------

func test_correction_decays_to_zero_over_duration() -> void:
    var track := PlotCorrectionTrack.new("number", 100.0)
    track.record(10.0, 0.0)
    assert_float(track.read(0.0)).is_equal_approx(10.0, 0.0001)
    assert_float(track.read(50.0)).is_equal_approx(5.0, 0.0001)  # k = 0.5
    assert_float(track.read(100.0)).is_equal_approx(0.0, 0.0001)  # elapsed>=duration
    assert_float(track.read(150.0)).is_equal_approx(0.0, 0.0001)

func test_correction_vec2_scaled() -> void:
    var track := PlotCorrectionTrack.new("vec2", 100.0)
    track.record({"x": 8.0, "y": 4.0}, 0.0)
    var r = track.read(25.0)  # k = 0.75
    assert_float(r["x"]).is_equal_approx(6.0, 0.0001)
    assert_float(r["y"]).is_equal_approx(3.0, 0.0001)

func test_correction_hard_clear_after_1000ms() -> void:
    var track := PlotCorrectionTrack.new("number", 100.0)
    track.record(10.0, 0.0)
    assert_float(track.read(1000.0)).is_equal_approx(0.0, 0.0001)
    # after hard clear, no record -> zero even at small elapsed
    assert_float(track.read(0.0)).is_equal_approx(0.0, 0.0001)

func test_correction_zero_without_record() -> void:
    var track := PlotCorrectionTrack.new("vec3", 100.0)
    var r = track.read(10.0)
    assert_float(r["x"]).is_equal_approx(0.0, 0.0001)
    assert_float(r["z"]).is_equal_approx(0.0, 0.0001)

# --- Predictor ----------------------------------------------------------

# Predict fn: state {pos:int}, input {dx:int} -> state {pos: pos+dx}.
func _move_predict(state: Variant, input: Variant, _player: Dictionary) -> Variant:
    state["pos"] = int(state["pos"]) + int(input["dx"])
    return state

func test_predictor_apply_advances_predicted() -> void:
    var p := PlotPredictor.new(_move_predict, {"id": "p1"})
    p.set_authoritative({"pos": 0})
    p.apply({"seq": 1, "input": {"dx": 5}})
    p.apply({"seq": 2, "input": {"dx": 3}})
    assert_int(p.predicted_state["pos"]).is_equal(8)

func test_predictor_deep_clone_isolates_authoritative() -> void:
    var p := PlotPredictor.new(_move_predict, {"id": "p1"})
    var auth := {"pos": 0}
    p.set_authoritative(auth)
    p.apply({"seq": 1, "input": {"dx": 9}})
    # authoritative source dict must be untouched by predicted mutation
    assert_int(auth["pos"]).is_equal(0)

func test_predictor_reconcile_replays_pending_no_drift() -> void:
    var p := PlotPredictor.new(_move_predict, {"id": "p1"})
    p.set_authoritative({"pos": 0})
    p.apply({"seq": 1, "input": {"dx": 5}})  # predicted pos = 5
    p.apply({"seq": 2, "input": {"dx": 5}})  # predicted pos = 10
    var drift := [-1.0]
    p.reconciled.connect(func(d): drift[0] = d)
    # server acked seq 1 (pos 5), seq 2 still pending -> replay gives pos 10
    p.reconcile({"pos": 5}, 1)
    assert_int(p.predicted_state["pos"]).is_equal(10)
    assert_float(drift[0]).is_equal_approx(0.0, 0.0001)

func test_predictor_reconcile_reports_drift() -> void:
    var p := PlotPredictor.new(_move_predict, {"id": "p1"})
    p.set_authoritative({"pos": 0})
    p.apply({"seq": 1, "input": {"dx": 5}})  # predicted pos = 5
    var drift := [-1.0]
    p.reconciled.connect(func(d): drift[0] = d)
    # server says pos=8 (e.g. another player pushed us), seq 1 acked, no pending
    # replayed = 8, predicted was 5 -> drift |5-8| = 3
    p.reconcile({"pos": 8}, 1)
    assert_int(p.predicted_state["pos"]).is_equal(8)
    assert_float(drift[0]).is_equal_approx(3.0, 0.0001)

func test_predictor_disable_resets_to_authoritative() -> void:
    var p := PlotPredictor.new(_move_predict, {"id": "p1"})
    p.set_authoritative({"pos": 0})
    p.apply({"seq": 1, "input": {"dx": 5}})
    p.disable()
    assert_bool(p.disabled).is_true()
    assert_int(p.predicted_state["pos"]).is_equal(0)
    # disabled apply is a no-op
    p.apply({"seq": 2, "input": {"dx": 5}})
    assert_int(p.predicted_state["pos"]).is_equal(0)

func test_predictor_json_diff_nested() -> void:
    var d := PlotPredictor._json_diff_magnitude({"a": {"b": 1.0}, "c": 2.0}, {"a": {"b": 4.0}, "c": 2.0})
    assert_float(d).is_equal_approx(3.0, 0.0001)
