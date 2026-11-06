extends Control
## Start screen: join a server, or host & play on this computer.
## Run with `-- --server` (Docker does this) to be a dedicated server instead.
##
## Test helpers (used by automated checks, safe to ignore):
##   -- --join=HOST:PORT --name=NAME --pin=1234 [--hero=glint] [--place=X,Y:type|X,Y:type]
##      [--upgrade=X,Y|X,Y] [--ready=1] [--quit-after=SECONDS]
##   Server only: -- --server --speed=8   (runs the simulation faster, for tests)
##   Screenshots (needs a display): --shot=/abs/path.png --shot-after=SECONDS
##      [--select=X,Y] [--preview-results=1] [--cam=X,Y,Z[,lookZ | ,lookX,lookZ]]

const SETTINGS_PATH := "user://settings.cfg"
const World := preload("res://scripts/world.gd")
const D := preload("res://scripts/data.gd")
const UI := preload("res://scripts/ui_theme.gd")
const CardButton := preload("res://scripts/card_button.gd")

var _address: LineEdit
var _port: SpinBox
var _name: LineEdit
var _pin: LineEdit
var _status: Label
var _buttons: Array[Button] = []
var _hero_buttons := {}
var _hero_info: Label
var _auto := {}


func _ready() -> void:
	_auto = _parse_args()
	if _auto.has("speed"):
		Engine.time_scale = float(_auto.speed)
	if _auto.has("hero"):
		Net.my_hero = _auto.hero
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
	if _auto.has("shot"):
		get_tree().create_timer(float(_auto.get("shot-after", "3"))).timeout.connect(_take_shot)
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
	theme = UI.theme()
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color("#0B1226"))
	grad.set_color(1, Color("#33226B"))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0)
	gt.fill_to = Vector2(0.5, 1)
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_add_stars()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# two columns: brand + hero | sign-in
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	center.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	left.add_theme_constant_override("separation", 10)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_child(left)

	var brand := HBoxContainer.new()
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", 10)
	left.add_child(brand)
	UI.picture(brand, load("res://icon.svg"), Vector2(84, 84))
	var bt := VBoxContainer.new()
	bt.add_theme_constant_override("separation", -6)
	brand.add_child(bt)
	UI.label(bt, "LANTERNFALL", 54, UI.GOLD, true, 12)
	UI.label(bt, "Keep Pip glowing!", 20, UI.LILAC, true, 6)

	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)

	var rib := UI.panel(left, "Ribbon")
	rib.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var rl := UI.label(rib, "CHOOSE YOUR HERO", 22, Color.WHITE, true, 7)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var heroes := HBoxContainer.new()
	heroes.alignment = BoxContainer.ALIGNMENT_CENTER
	heroes.add_theme_constant_override("separation", 22)
	left.add_child(heroes)
	for h in D.HERO_ORDER:
		var hb := CardButton.new()
		hb.name = "Hero_" + h
		heroes.add_child(hb)
		hb.setup(UI.icon(h), D.HEROES[h].name, Vector2(170, 200), "", D.HEROES[h].role)
		hb.pressed.connect(_pick_hero.bind(h))
		_hero_buttons[h] = hb
	var info := UI.panel(left, "SoftPanel")
	_hero_info = UI.label(info, "", 17, UI.CREAM)
	_hero_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_info.custom_minimum_size = Vector2(396, 0)
	_pick_hero(cfg.get_value("join", "hero", Net.my_hero))

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var sh := UI.label(box, "SIGN IN", 30, UI.GOLD, true, 8)
	sh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

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

	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	var join := UI.button(box, "JOIN GAME", "GoldButton", _on_join, Vector2(0, 68))
	join.add_theme_font_size_override("font_size", 26)
	var host := UI.button(box, "Host & play on this computer", "Button", _on_host, Vector2(0, 56))
	_buttons = [join, host]

	_status = UI.label(box, "", 16, UI.LILAC)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(380, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var ver := UI.label(left, "Version %s" % Net.GAME_VERSION, 14, Color("#6E78A8"))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## A sprinkle of twinkly stars on the night sky.
func _add_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 70:
		var s := ColorRect.new()
		var r := rng.randf_range(1.5, 3.5)
		s.color = Color(1, 0.95, 0.8, rng.randf_range(0.25, 0.8))
		s.anchor_left = rng.randf()
		s.anchor_top = rng.randf() * 0.85
		s.anchor_right = s.anchor_left
		s.anchor_bottom = s.anchor_top
		s.offset_left = 0
		s.offset_top = 0
		s.offset_right = r
		s.offset_bottom = r
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)


func _field(parent: Node, label: String, value: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	_labelled(parent, label, e)
	return e


func _labelled(parent: Node, label: String, control: Control) -> void:
	UI.label(parent, label, 16, UI.LILAC)
	parent.add_child(control)


func _pick_hero(h: String) -> void:
	if not D.HEROES.has(h):
		h = "bramble"
	Net.my_hero = h
	for k in _hero_buttons:
		_hero_buttons[k].set_selected(k == h)
	var d: Dictionary = D.HEROES[h]
	_hero_info.text = "%s\n%s (Q): %s" % [d.passive, d.ability, d.ability_text]


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("join", "hero", Net.my_hero)
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
		if _auto.has("place") or _auto.has("ready"):
			_auto_place.call_deferred(_auto.get("place", ""))
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
	var w := get_tree().root.get_node_or_null("World")
	if w == null:
		return
	if _auto.has("ready"):
		_auto_ready(w)
	if spec == "":
		return
	for item in spec.split("|"):
		var parts := item.split(":")
		var xy := parts[0].split(",")
		var c := Vector2i(int(xy[0]), int(xy[1]))
		w.debug_move_hero(c)
		await get_tree().create_timer(0.25).timeout
		w.place_tower(c, parts[1] if parts.size() > 1 else "hedge_block")
		await get_tree().create_timer(0.2).timeout
	if _auto.has("select"):
		var sxy := String(_auto.select).split(",")
		w.selected_cell = Vector2i(int(sxy[0]), int(sxy[1]))
		w.hud.refresh()
	if _auto.has("cam"):
		var cv := String(_auto.cam).split(",")
		w.view.camera.position = Vector3(float(cv[0]), float(cv[1]), float(cv[2]))
		if cv.size() >= 5:
			w.view.camera.look_at(Vector3(float(cv[3]), -0.6, float(cv[4])))
		else:
			w.view.camera.look_at(Vector3(0, -0.6, float(cv[3]) if cv.size() > 3 else 0.0))
	if _auto.has("preview-results"):
		w.hud.preview_results = true
		w.hud.refresh()
	if _auto.has("upgrade"):
		await get_tree().create_timer(0.5).timeout
		for item in String(_auto.upgrade).split("|"):
			var xy := item.split(",")
			var c := Vector2i(int(xy[0]), int(xy[1]))
			w.debug_move_hero(c)
			await get_tree().create_timer(0.25).timeout
			w.selected_cell = c
			w.upgrade_selected()
			await get_tree().create_timer(0.2).timeout


## Test helper: press Ready whenever a build phase starts, and keep spending
## coins on upgrades so long automated matches stay meaningful.
func _auto_ready(w: Node) -> void:
	while is_instance_valid(w):
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(w):
			return
		if w.phase == "build" and not w.ready_names.has(Net.my_name):
			for c in w.towers:
				if w.towers[c].owner == Net.my_name and w.upgrade_cost(Net.my_name, c) > 0 and w.my_coins() >= w.upgrade_cost(Net.my_name, c):
					w.debug_move_hero(c)
					await get_tree().create_timer(0.25).timeout
					w.selected_cell = c
					w.upgrade_selected()
					await get_tree().create_timer(0.2).timeout
			w.toggle_ready()


func _take_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(String(_auto.shot))
	print("[shot] saved ", _auto.shot)
