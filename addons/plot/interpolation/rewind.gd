# A lightweight handle bound to a fixed past server timestamp. Lets callers
# read several paths at one frozen time without repeating the timestamp (e.g.
# hit detection across multiple entities at a shot's server time). Thin wrapper
# over PlotSampler.sample_at.
extends RefCounted
class_name PlotRewind

var _buffer: PlotSnapshotBuffer
var at_server_ts: float

func _init(buffer: PlotSnapshotBuffer, p_at_server_ts: float) -> void:
    _buffer = buffer
    at_server_ts = p_at_server_ts

# Sample one path at this handle's bound timestamp. See PlotSampler.sample_at
# for the return-value contract.
func sample(path: String, type: String):
    return PlotSampler.sample_at(_buffer, path, type, at_server_ts)
