@tool
extends EditorPlugin

# Editor entry point for the Plot SDK. Adds the Plot status dock when the plugin
# is enabled and removes it on disable. Runtime classes (PlotClient, PlotRoom,
# …) are plain class_name scripts and need no registration here.

const PlotDock := preload("res://addons/plot/editor/plot_dock.gd")

var _dock: Control

func _enter_tree() -> void:
    _dock = PlotDock.new()
    add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)

func _exit_tree() -> void:
    if _dock != null:
        remove_control_from_docks(_dock)
        _dock.free()
        _dock = null
