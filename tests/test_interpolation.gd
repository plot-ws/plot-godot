extends GdUnitTestSuite

# --- Lerp ---------------------------------------------------------------

func test_lerp_number_midpoint() -> void:
    assert_float(PlotLerp.lerp_number(0.0, 10.0, 0.5)).is_equal_approx(5.0, 0.0001)

func test_lerp_number_endpoints() -> void:
    assert_float(PlotLerp.lerp_number(2.0, 8.0, 0.0)).is_equal_approx(2.0, 0.0001)
    assert_float(PlotLerp.lerp_number(2.0, 8.0, 1.0)).is_equal_approx(8.0, 0.0001)

func test_lerp_vec2_midpoint() -> void:
    var r := PlotLerp.lerp_vec2({"x": 0.0, "y": 0.0}, {"x": 4.0, "y": 8.0}, 0.5)
    assert_float(r["x"]).is_equal_approx(2.0, 0.0001)
    assert_float(r["y"]).is_equal_approx(4.0, 0.0001)

func test_lerp_vec3_quarter() -> void:
    var r := PlotLerp.lerp_vec3({"x": 0.0, "y": 0.0, "z": 0.0}, {"x": 4.0, "y": 8.0, "z": 12.0}, 0.25)
    assert_float(r["x"]).is_equal_approx(1.0, 0.0001)
    assert_float(r["y"]).is_equal_approx(2.0, 0.0001)
    assert_float(r["z"]).is_equal_approx(3.0, 0.0001)

func test_lerp_quat_endpoints_exact() -> void:
    var a := {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0}
    var b := {"x": 0.0, "y": 1.0, "z": 0.0, "w": 0.0}
    var r0 := PlotLerp.lerp_quat(a, b, 0.0)
    assert_float(r0["w"]).is_equal_approx(1.0, 0.0001)
    var r1 := PlotLerp.lerp_quat(a, b, 1.0)
    assert_float(r1["y"]).is_equal_approx(1.0, 0.0001)

func test_lerp_quat_stays_unit_length() -> void:
    var a := {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0}
    var b := {"x": 0.0, "y": 0.7071, "z": 0.0, "w": 0.7071}
    var r := PlotLerp.lerp_quat(a, b, 0.5)
    var mag: float = sqrt(r["x"] * r["x"] + r["y"] * r["y"] + r["z"] * r["z"] + r["w"] * r["w"])
    assert_float(mag).is_equal_approx(1.0, 0.001)

# --- SnapshotBuffer -----------------------------------------------------

func test_buffer_lookup_brackets_target() -> void:
    var buf := PlotSnapshotBuffer.new(500.0)
    buf.push(100.0, {"v": 1})
    buf.push(200.0, {"v": 2})
    buf.push(300.0, {"v": 3})
    var pair = buf.lookup(250.0)
    assert_float(pair["a"]["ts"]).is_equal_approx(200.0, 0.0001)
    assert_float(pair["b"]["ts"]).is_equal_approx(300.0, 0.0001)

func test_buffer_lookup_clamps_to_ends() -> void:
    var buf := PlotSnapshotBuffer.new(500.0)
    buf.push(100.0, {"v": 1})
    buf.push(200.0, {"v": 2})
    var before = buf.lookup(50.0)
    assert_float(before["a"]["ts"]).is_equal_approx(100.0, 0.0001)
    assert_object(before["b"]).is_null()
    var after = buf.lookup(999.0)
    assert_float(after["a"]["ts"]).is_equal_approx(200.0, 0.0001)
    assert_object(after["b"]).is_null()

func test_buffer_rejects_non_monotonic() -> void:
    var buf := PlotSnapshotBuffer.new(500.0)
    buf.push(200.0, {"v": 1})
    buf.push(150.0, {"v": 2})  # ignored: ts <= last
    assert_int(buf.size).is_equal(1)

func test_buffer_evicts_beyond_horizon() -> void:
    var buf := PlotSnapshotBuffer.new(100.0)
    buf.push(0.0, {"v": 0})
    buf.push(50.0, {"v": 1})
    buf.push(120.0, {"v": 2})
    # cutoff = 120 - 100 = 20; snapshots[1]=50 >= 20 so head (0) is kept as
    # left anchor only until next snapshot within horizon.
    buf.push(200.0, {"v": 3})
    # cutoff = 100; snapshots[1] (50) < 100 -> drop head (0). Then snapshots[1]
    # (120) >= 100 -> stop. Oldest should be 50.
    assert_float(buf.oldest["ts"]).is_equal_approx(50.0, 0.0001)

func test_buffer_empty_lookup_null() -> void:
    var buf := PlotSnapshotBuffer.new(500.0)
    assert_object(buf.lookup(0.0)).is_null()

# --- ServerClock --------------------------------------------------------

func test_clock_offset_is_median_odd() -> void:
    var c := PlotServerClock.new()
    c.observe(110.0, 100.0)  # 10
    c.observe(130.0, 100.0)  # 30
    c.observe(120.0, 100.0)  # 20
    assert_float(c.offset).is_equal_approx(20.0, 0.0001)

func test_clock_offset_is_median_even() -> void:
    var c := PlotServerClock.new()
    c.observe(110.0, 100.0)  # 10
    c.observe(140.0, 100.0)  # 40
    c.observe(120.0, 100.0)  # 20
    c.observe(130.0, 100.0)  # 30
    # sorted [10,20,30,40] -> (20+30)/2 = 25
    assert_float(c.offset).is_equal_approx(25.0, 0.0001)

func test_clock_window_caps_at_eight() -> void:
    var c := PlotServerClock.new()
    for i in range(10):
        c.observe(100.0 + i, 100.0)  # offsets 0..9
    # only last 8 kept: offsets 2..9, median (5+6)/2 = 5.5
    assert_float(c.offset).is_equal_approx(5.5, 0.0001)

func test_clock_jitter_zero_with_one_sample() -> void:
    var c := PlotServerClock.new()
    c.observe(110.0, 100.0)
    assert_float(c.jitter).is_equal_approx(0.0, 0.0001)

func test_clock_jitter_population_stddev() -> void:
    var c := PlotServerClock.new()
    c.observe(100.0, 100.0)  # 0
    c.observe(120.0, 100.0)  # 20
    # mean 10, variance ((0-10)^2 + (20-10)^2)/2 = 100, stddev 10
    assert_float(c.jitter).is_equal_approx(10.0, 0.0001)

# --- PathResolver -------------------------------------------------------

func test_path_resolver_simple() -> void:
    var leaves := PlotPathResolver.resolve("a.b", {"a": {"b": 1}}, {"a": {"b": 2}})
    assert_int(leaves.size()).is_equal(1)
    assert_str(leaves[0]["path"]).is_equal("a.b")
    assert_int(leaves[0]["value_a"]).is_equal(1)
    assert_int(leaves[0]["value_b"]).is_equal(2)

func test_path_resolver_wildcard_expands_union() -> void:
    var a := {"players": {"p1": {"x": 1}, "p2": {"x": 2}}}
    var b := {"players": {"p2": {"x": 3}, "p3": {"x": 4}}}
    var leaves := PlotPathResolver.resolve("players.*.x", a, b)
    # union keys p1,p2,p3 sorted
    assert_int(leaves.size()).is_equal(3)
    assert_str(leaves[0]["path"]).is_equal("players.p1.x")
    assert_str(leaves[1]["path"]).is_equal("players.p2.x")
    assert_str(leaves[2]["path"]).is_equal("players.p3.x")
    # p1 only in a, p3 only in b
    assert_int(leaves[0]["value_a"]).is_equal(1)
    assert_bool(PlotPathResolver.is_missing(leaves[0]["value_b"])).is_true()
    assert_bool(PlotPathResolver.is_missing(leaves[2]["value_a"])).is_true()
    assert_int(leaves[2]["value_b"]).is_equal(4)

func test_path_resolver_missing_for_absent() -> void:
    var leaves := PlotPathResolver.resolve("a.b.c", {"a": {}}, {"a": {}})
    assert_bool(PlotPathResolver.is_missing(leaves[0]["value_a"])).is_true()

# --- Interpolator -------------------------------------------------------

func test_interpolator_lerps_number_path() -> void:
    var buf := PlotSnapshotBuffer.new(500.0)
    buf.push(100.0, {"score": 0.0})
    buf.push(200.0, {"score": 100.0})
    var interp := PlotInterpolator.new("score", "number", 0.0)
    var out := interp.tick(150.0, buf)
    assert_float(out["score"]).is_equal_approx(50.0, 0.0001)

func test_interpolator_wildcard_vec2() -> void:
    var buf := PlotSnapshotBuffer.new(500.0)
    buf.push(0.0, {"p": {"a": {"x": 0.0, "y": 0.0}}})
    buf.push(100.0, {"p": {"a": {"x": 10.0, "y": 20.0}}})
    var interp := PlotInterpolator.new("p.*", "vec2", 0.0)
    var out := interp.tick(50.0, buf)
    assert_float(out["p.a"]["x"]).is_equal_approx(5.0, 0.0001)
    assert_float(out["p.a"]["y"]).is_equal_approx(10.0, 0.0001)

func test_interpolator_single_snapshot_emits_a() -> void:
    var buf := PlotSnapshotBuffer.new(500.0)
    buf.push(100.0, {"score": 42.0})
    var interp := PlotInterpolator.new("score", "number", 0.0)
    var out := interp.tick(100.0, buf)
    assert_float(out["score"]).is_equal_approx(42.0, 0.0001)
