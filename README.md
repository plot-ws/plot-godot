# Plot Godot SDK

GDScript multiplayer SDK for Godot 4.4+.

## Install

Copy `addons/plot/` into your project's `addons/` directory, then enable
the **Plot** plugin in `Project → Project Settings → Plugins`.

## Quickstart

```gdscript
var plot := PlotClient.new({
    "app_key": "pl_pub_live_xxx",
    "player_id": OS.get_unique_id(),
})
add_child(plot)

var room: PlotRoom = await plot.join({ "room_code": "LOBBY1" })
room.message_received.connect(func(from, data):
    print("%s: %s" % [from, data]))
room.player_joined.connect(func(pid): print("joined: ", pid))
room.player_left.connect(func(pid): print("left: ", pid))
room.send({ "hello": "world" })
```

## Interpolation (v1f)

Smoothly render remote state by interpolating between server snapshots:

```gdscript
room.interpolate("players.*.position", "vec2", 100.0)
room.frame_emitted.connect(func(interpolated: Dictionary, ts: float):
    for path in interpolated:
        render_at(path, interpolated[path]))

# Drive the frame loop from _process(delta):
func _process(_delta):
    room.tick_frame()
# ...or start the built-in SceneTreeTimer loop:
room.start_frame_loop(16.0)

# Grow the render delay on jittery connections:
room.set_adaptive_smoothing(true, 1.0, 100.0)
```

Supported types: `"number"`, `"vec2"`, `"vec3"`, `"quat"`; vector/quat values
are `{x, y, z[, w]}` dictionaries. Paths support a single-level `*` wildcard.

## Client-side prediction (v1g)

Apply local inputs immediately and reconcile against the server's
authoritative state. The engine cannot run your server handler, so you supply
a deterministic `Callable(state, input, player) -> state`:

```gdscript
room.attach_prediction(initial_state, func(state, input, player):
    return reduce(state, input, player))

room.predict("players.me.position", "vec2", 100.0)
room.predicted.connect(func(state, ts, drift): render(state))
room.send_predicted({ "move": "left" }) # optimistic; carries _seq upstream

var pos = room.corrected_state["players.me.position"]
print(room.predicted_state)
```

## Protocol

`addons/plot/protocol.gd` is generated from `packages/protocol/codegen/`.
Do not hand-edit. SDK speaks `X-Plot-Protocol: v1b.0`.

## Tests

`tests/test_plot.gd` uses GdUnit4. CI runs Godot 4.4 headless via
`chickensoft-games/setup-godot`.
