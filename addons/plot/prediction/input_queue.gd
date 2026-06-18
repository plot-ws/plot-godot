# Bounded queue of pending (unacked) predicted inputs.
#
# Ports handler-client/input-queue.ts. Entries must have monotonically
# increasing seq. Capped at 200; pushing beyond the cap drops the oldest entry
# and reports overflow (return value + `overflowed` signal).
class_name PlotInputQueue
extends RefCounted

signal overflowed(dropped_seq: int)

const CAP := 200

# Each entry: { "seq": int, "input": Variant }.
var _entries: Array = []

# Returns true if the push caused an overflow (oldest entry dropped).
func push(entry: Dictionary) -> bool:
    var seq := int(entry["seq"])
    if _entries.size() > 0:
        var last: Dictionary = _entries[_entries.size() - 1]
        assert(
            seq > int(last["seq"]),
            "InputQueue: seq must be monotonically increasing (got %d after %d)" % [seq, int(last["seq"])]
        )
    _entries.append(entry)
    if _entries.size() > CAP:
        var dropped: Dictionary = _entries.pop_front()
        overflowed.emit(int(dropped["seq"]))
        return true
    return false

func ack_up_to(seq: int) -> void:
    while _entries.size() > 0 and int(_entries[0]["seq"]) <= seq:
        _entries.pop_front()

func pending() -> Array:
    return _entries

var size: int:
    get:
        return _entries.size()

func clear() -> void:
    _entries.clear()
