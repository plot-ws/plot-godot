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

## Protocol

`addons/plot/protocol.gd` is generated from `packages/protocol/codegen/`.
Do not hand-edit. SDK speaks `X-Plot-Protocol: v1b.0`.

## Tests

`tests/test_plot.gd` uses GdUnit4. CI runs Godot 4.4 headless via
`chickensoft-games/setup-godot`.
