extends Control
## Start screen: join a server, or host & play on this computer.
## Run with `-- --server` (Docker does this) to be a dedicated server instead.
##
## Test helpers (used by automated checks, safe to ignore):
##   -- --join=HOST:PORT --name=NAME --pin=1234 [--place=X,Y:type|X,Y:type] [--quit-after=SECONDS]

const SETTINGS_PATH := "user://settings.cfg"
const World := preload("res://scripts/world.gd")

var _address: LineEdit
var _port: SpinBox
var _name: LineEdit
var _pin: LineEdit
var _status: Label
var _buttons: Array[Button] = []
var _auto := {}


func _ready() -> void:
	_auto = _parse_args()
	if Net.is_dedicated:
		var port := int(OS.get_environment("LANTERNFALL_PORT")) if OS.get_environment("LANTERNFALL_PORT") != "" else Net.DEFAULT_PORT
		if Net.start_server(port) != OK:
			push_error("Could not start the server on port %d" % port)
			get_tree().quit(1)
			return
		_enter_world()
		return
	Net.login_finished.connect(_on_login_finished)
	Net.connection_lost.connect(_on_connection_lost)
	_build_ui()
	if _auto.has("join"):
		var parts: PackedStringArray = _auto.join.split(":")
		Net.join(parts[0], int(parts[1]) if parts.size() > 1 else Net.DEFAULT_PORT, _auto.get("name", "Tester"), _auto.get("pin", "1234"))
	if _auto.has("quit-after"):
		get_tree().create_timer(float(_auto["quit-after"])).timeout.connect(func(): get_tree().quit())


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#0B1226")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var icon := TextureRect.new()
	icon.texture = load("res://icon.svg")
	icon.custom_minimum_size = Vector2(120, 120)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)

	var title := Label.new()
	title.text = "LANTERNFALL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color("#FFC44D"))
	box.add_child(title)

	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)

	_address = _field(box, "Server address", cfg.get_value("join", "address", "127.0.0.1"))
	_address.name = "AddressEdit"
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = cfg.get_value("join", "port", Net.DEFAULT_PORT)
	_labelled(box, "Port", _port)
	_name = _field(box, "Your name", cfg.get_value("join", "name", ""))
	_name.name = "NameEdit"
	_name.placeholder_text = "e.g. Cade"
	_pin = _field(box, "PIN (4–6 digits)", "")
	_pin.name = "PinEdit"
	_pin.secret = true
	_pin.max_length = 6

	var join := Button.new()
	join.text = "Join game"
	join.custom_minimum_size.y = 48
	join.pressed.connect(_on_join)
	box.add_child(join)
	var host := Button.new()
	host.text = "Host & play on this computer"
	host.pressed.connect(_on_host)
	box.add_child(host)
	_buttons = [join, host]

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("#B9C2DA"))
	box.add_child(_status)

	var ver := Label.new()
	ver.text = "Version %s" % Net.GAME_VERSION
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_color_override("font_color", Color("#5E6B8C"))
	box.add_child(ver)


func _field(parent: Node, label: String, value: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	_labelled(parent, label, e)
	return e


func _labelled(parent: Node, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	parent.add_child(control)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("join", "address", _address.text)
	cfg.set_value("join", "port", int(_port.value))
	cfg.set_value("join", "name", _name.text)
	cfg.save(SETTINGS_PATH)


func _busy(text: String) -> void:
	_status.text = text
	for b in _buttons:
		b.disabled = true


func _on_join() -> void:
	_save_settings()
	_busy("Connecting…")
	Net.join(_address.text.strip_edges(), int(_port.value), _name.text, _pin.text)


func _on_host() -> void:
	_save_settings()
	_busy("Starting a game on this computer…")
	Net.host_and_play(int(_port.value), _name.text, _pin.text)


func _on_login_finished(ok: bool, message: String) -> void:
	if ok:
		print("[%s] %s" % [Net.my_name, message])
		_enter_world()
		if _auto.has("place"):
			_auto_place.call_deferred(_auto.place)
		return
	print("[client] login failed: %s" % message)
	if _status:
		_status.text = message
		for b in _buttons:
			b.disabled = false


func _on_connection_lost(message: String) -> void:
	var w := get_tree().root.get_node_or_null("World")
	if w:
		w.queue_free()
	visible = true
	if _status:
		_status.text = message
		for b in _buttons:
			b.disabled = false


func _enter_world() -> void:
	var world := World.new()
	world.name = "World"
	get_tree().root.add_child.call_deferred(world)
	visible = false


func _auto_place(spec: String) -> void:
	await get_tree().create_timer(1.0).timeout
	for item in spec.split("|"):
		var parts := item.split(":")
		var xy := parts[0].split(",")
		var w := get_tree().root.get_node_or_null("World")
		if w:
			w.place_tower(Vector2i(int(xy[0]), int(xy[1])), parts[1] if parts.size() > 1 else "hedge_block")
		await get_tree().create_timer(0.15).timeout
