@tool
extends Control

# Editor-only dock for the Plot SDK. Surfaces the protocol version the runtime
# speaks, lets a developer stash an app key + server URL while integrating, and
# pings the connect endpoint to confirm reachability. Built entirely in code so
# there is no .tscn/UID to import; added to the editor by plugin.gd.

const DEFAULT_API_URL := "https://api.plot.ws"
const DOCS_URL := "https://plot.ws/docs"
const DOCS_GODOT_URL := "https://plot.ws/docs/sdks/godot"
const APP_KEY_SETTING := "plot/editor/app_key"
const API_URL_SETTING := "plot/editor/api_url"

var _app_key_edit: LineEdit
var _api_url_edit: LineEdit
var _test_button: Button
var _status_label: RichTextLabel
var _http: HTTPRequest
var _testing := false

func _init() -> void:
    name = "Plot"

func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)

    var root := VBoxContainer.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation", 8)
    add_child(root)

    var title := Label.new()
    title.text = "Plot Multiplayer SDK"
    title.add_theme_font_size_override("font_size", 16)
    root.add_child(title)

    var proto := Label.new()
    proto.text = "Protocol: X-Plot-Protocol: %s" % PlotProtocol.SCHEMA_VERSION
    proto.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
    root.add_child(proto)

    root.add_child(HSeparator.new())

    var conn := Label.new()
    conn.text = "Connection"
    root.add_child(conn)

    _app_key_edit = _add_field(root, "App Key", _load_setting(APP_KEY_SETTING, ""))
    _app_key_edit.text_changed.connect(func(text): _save_setting(APP_KEY_SETTING, text))

    _api_url_edit = _add_field(root, "Server URL", _load_setting(API_URL_SETTING, DEFAULT_API_URL))
    _api_url_edit.text_changed.connect(func(text): _save_setting(API_URL_SETTING, text))

    var buttons := HBoxContainer.new()
    root.add_child(buttons)

    _test_button = Button.new()
    _test_button.text = "Test connection"
    _test_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _test_button.pressed.connect(_on_test_pressed)
    buttons.add_child(_test_button)

    var reset_button := Button.new()
    reset_button.text = "Reset"
    reset_button.pressed.connect(_on_reset_pressed)
    buttons.add_child(reset_button)

    _status_label = RichTextLabel.new()
    _status_label.fit_content = true
    _status_label.bbcode_enabled = true
    _status_label.custom_minimum_size = Vector2(0, 40)
    root.add_child(_status_label)

    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(spacer)

    var docs := Label.new()
    docs.text = "Documentation"
    root.add_child(docs)
    root.add_child(_link_button("Plot docs", DOCS_URL))
    root.add_child(_link_button("Godot SDK guide", DOCS_GODOT_URL))

    _http = HTTPRequest.new()
    add_child(_http)
    _http.request_completed.connect(_on_request_completed)

func _add_field(parent: VBoxContainer, label_text: String, value: String) -> LineEdit:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size = Vector2(80, 0)
    row.add_child(label)
    var edit := LineEdit.new()
    edit.text = value
    edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(edit)
    return edit

func _link_button(label_text: String, url: String) -> Button:
    var button := Button.new()
    button.text = label_text
    button.flat = true
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.pressed.connect(func(): OS.shell_open(url))
    return button

func _on_test_pressed() -> void:
    if _testing:
        return
    var app_key := _app_key_edit.text.strip_edges()
    if app_key.is_empty():
        _set_status("Enter an app key before testing.", Color(0.9, 0.7, 0.3))
        return
    var api_url := _api_url_edit.text.strip_edges()
    if not (api_url.begins_with("http://") or api_url.begins_with("https://")):
        _set_status("Server URL must start with http:// or https://", Color(0.9, 0.4, 0.4))
        return

    var connect_url := api_url.trim_suffix("/") + "/v1/connect"
    var body := JSON.stringify({"appKey": app_key, "playerId": "editor-probe"})
    var headers := [
        "Content-Type: application/json",
        "X-Plot-Protocol: " + PlotProtocol.SCHEMA_VERSION,
    ]
    var err := _http.request(connect_url, headers, HTTPClient.METHOD_POST, body)
    if err != OK:
        _set_status("Could not start request (error %d)." % err, Color(0.9, 0.4, 0.4))
        return
    _testing = true
    _test_button.disabled = true
    _test_button.text = "Testing…"
    _set_status("Connecting to %s…" % connect_url, Color(0.7, 0.7, 0.7))

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
    _testing = false
    _test_button.disabled = false
    _test_button.text = "Test connection"
    if result != HTTPRequest.RESULT_SUCCESS:
        _set_status("Connection failed (result %d)." % result, Color(0.9, 0.4, 0.4))
        return
    if response_code >= 200 and response_code < 300:
        _set_status("Reachable — server replied %d." % response_code, Color(0.5, 0.8, 0.5))
    else:
        _set_status(
            "Reached server but it rejected the request (HTTP %d). Check the app key." % response_code,
            Color(0.9, 0.7, 0.3))

func _on_reset_pressed() -> void:
    _app_key_edit.text = ""
    _api_url_edit.text = DEFAULT_API_URL
    _save_setting(APP_KEY_SETTING, "")
    _save_setting(API_URL_SETTING, DEFAULT_API_URL)
    _set_status("", Color.WHITE)

func _set_status(message: String, color: Color) -> void:
    if _status_label == null:
        return
    if message.is_empty():
        _status_label.text = ""
        return
    _status_label.text = "[color=#%s]%s[/color]" % [color.to_html(false), message]

func _load_setting(key: String, fallback: String) -> String:
    if Engine.is_editor_hint() and EditorInterface.get_editor_settings().has_setting(key):
        return str(EditorInterface.get_editor_settings().get_setting(key))
    return fallback

func _save_setting(key: String, value: String) -> void:
    if Engine.is_editor_hint():
        EditorInterface.get_editor_settings().set_setting(key, value)
