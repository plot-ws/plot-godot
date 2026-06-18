# Estimates the client/server clock offset from observed snapshot timestamps.
#
# Ports interpolation/server-clock.ts. `offset` is the median of the last 8
# (client_now - server_ts) samples; `jitter` is the population standard
# deviation of that window (0 with fewer than two samples).
class_name PlotServerClock

const WINDOW := 8

var _samples: Array[float] = []

func observe(client_now: float, server_ts: float) -> void:
    _samples.append(client_now - server_ts)
    if _samples.size() > WINDOW:
        _samples.pop_front()

var offset: float:
    get:
        if _samples.size() == 0:
            return 0.0
        var sorted := _samples.duplicate()
        sorted.sort()
        var mid := sorted.size() >> 1
        if sorted.size() % 2 == 1:
            return sorted[mid]
        return (sorted[mid - 1] + sorted[mid]) / 2.0

# Population standard deviation of the offset window — a proxy for jitter.
# Returns 0 with fewer than two samples.
var jitter: float:
    get:
        var n := _samples.size()
        if n < 2:
            return 0.0
        var total := 0.0
        for s in _samples:
            total += s
        var mean := total / n
        var variance := 0.0
        for s in _samples:
            variance += (s - mean) * (s - mean)
        variance /= n
        return sqrt(variance)
