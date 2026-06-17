extends GdUnitTestSuite

func test_room_constructs_with_player_and_transport() -> void:
    var transport := PlotTransport.new()
    var room := PlotRoom.new("p1", transport)
    assert_that(room).is_not_null()

func test_protocol_schema_version_is_defined() -> void:
    assert_that(PlotProtocol.SCHEMA_VERSION).is_equal("v1b.0")
