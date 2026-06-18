extends GdUnitTestSuite

# Point sampling of interpolated state at an arbitrary past server timestamp.
# Mirrors packages/client/test/interpolation/sampler.test.ts.

func _vec2_buffer() -> PlotSnapshotBuffer:
    var buf := PlotSnapshotBuffer.new(500.0)
    buf.push(100.0, {"positions": {"p1": {"x": 0.0, "y": 0.0}, "p2": {"x": 100.0, "y": 0.0}}})
    buf.push(200.0, {"positions": {"p1": {"x": 10.0, "y": 20.0}, "p2": {"x": 80.0, "y": 40.0}}})
    return buf

func test_sample_at_plain_path_midpoint() -> void:
    var buf := _vec2_buffer()
    var v = PlotSampler.sample_at(buf, "positions.p1", "vec2", 150.0)
    assert_float(v["x"]).is_equal_approx(5.0, 0.0001)
    assert_float(v["y"]).is_equal_approx(10.0, 0.0001)

func test_sample_at_number_off_centre() -> void:
    var buf := PlotSnapshotBuffer.new(500.0)
    buf.push(0.0, {"score": 0.0})
    buf.push(100.0, {"score": 50.0})
    var v = PlotSampler.sample_at(buf, "score", "number", 25.0)
    assert_float(v).is_equal_approx(12.5, 0.0001)

func test_sample_at_wildcard_expands_to_map() -> void:
    var buf := _vec2_buffer()
    var m = PlotSampler.sample_at(buf, "positions.*", "vec2", 150.0)
    assert_int(m.size()).is_equal(2)
    assert_float(m["positions.p1"]["x"]).is_equal_approx(5.0, 0.0001)
    assert_float(m["positions.p1"]["y"]).is_equal_approx(10.0, 0.0001)
    assert_float(m["positions.p2"]["x"]).is_equal_approx(90.0, 0.0001)
    assert_float(m["positions.p2"]["y"]).is_equal_approx(20.0, 0.0001)

func test_sample_at_before_horizon_null() -> void:
    var buf := _vec2_buffer()
    assert_object(PlotSampler.sample_at(buf, "positions.p1", "vec2", 50.0)).is_null()

func test_sample_at_after_horizon_null() -> void:
    var buf := _vec2_buffer()
    assert_object(PlotSampler.sample_at(buf, "positions.p1", "vec2", 250.0)).is_null()

func test_sample_at_empty_buffer_null() -> void:
    var buf := PlotSnapshotBuffer.new(500.0)
    assert_object(PlotSampler.sample_at(buf, "positions.p1", "vec2", 150.0)).is_null()

func test_sample_at_wildcard_outside_horizon_null() -> void:
    var buf := _vec2_buffer()
    assert_object(PlotSampler.sample_at(buf, "positions.*", "vec2", 9999.0)).is_null()

func test_sample_at_absent_plain_path_null() -> void:
    var buf := _vec2_buffer()
    assert_object(PlotSampler.sample_at(buf, "positions.ghost", "vec2", 150.0)).is_null()

func test_sample_at_endpoints_exact() -> void:
    var buf := _vec2_buffer()
    var newest = PlotSampler.sample_at(buf, "positions.p1", "vec2", 200.0)
    assert_float(newest["x"]).is_equal_approx(10.0, 0.0001)
    assert_float(newest["y"]).is_equal_approx(20.0, 0.0001)
    var oldest = PlotSampler.sample_at(buf, "positions.p1", "vec2", 100.0)
    assert_float(oldest["x"]).is_equal_approx(0.0, 0.0001)
    assert_float(oldest["y"]).is_equal_approx(0.0, 0.0001)

func test_sample_at_wildcard_emits_present_side() -> void:
    var buf := PlotSnapshotBuffer.new(500.0)
    buf.push(100.0, {"positions": {}})
    buf.push(200.0, {"positions": {"p1": {"x": 5.0, "y": 5.0}}})
    var m = PlotSampler.sample_at(buf, "positions.*", "vec2", 150.0)
    assert_int(m.size()).is_equal(1)
    assert_float(m["positions.p1"]["x"]).is_equal_approx(5.0, 0.0001)
    assert_float(m["positions.p1"]["y"]).is_equal_approx(5.0, 0.0001)

func test_rewind_samples_multiple_paths_at_one_timestamp() -> void:
    var buf := _vec2_buffer()
    var r := PlotRewind.new(buf, 150.0)
    assert_float(r.at_server_ts).is_equal_approx(150.0, 0.0001)
    var p1 = r.sample("positions.p1", "vec2")
    var p2 = r.sample("positions.p2", "vec2")
    assert_float(p1["x"]).is_equal_approx(5.0, 0.0001)
    assert_float(p2["x"]).is_equal_approx(90.0, 0.0001)
    var m = r.sample("positions.*", "vec2")
    assert_int(m.size()).is_equal(2)

func test_rewind_outside_horizon_null_every_path() -> void:
    var buf := _vec2_buffer()
    var r := PlotRewind.new(buf, 10.0)
    assert_object(r.sample("positions.p1", "vec2")).is_null()
    assert_object(r.sample("positions.*", "vec2")).is_null()
