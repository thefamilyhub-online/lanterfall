extends CanvasLayer
## Phase 0 HUD: Pip's glow, who's playing, tower picker and short messages.

var _world: Node
var _glow_bar: ProgressBar
var _players_label: Label
var _message: Label
var _message_timer := 0.0
var _buttons: Dictionary = {}


func setup(world: Node) -> void:
	_world = world
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 16)
	add_child(root)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	var title := Label.new()
	title.text = "LANTERNFALL · Phase 0 test"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#FFC44D"))
	col.add_child(title)

	var glow_row := HBoxContainer.new()
	var glow_label := Label.new()
	glow_label.text = "Pip's glow"
	glow_row.add_child(glow_label)
	_glow_bar = ProgressBar.new()
	_glow_bar.custom_minimum_size = Vector2(220, 20)
	_glow_bar.max_value = 100
	_glow_bar.value = 100
	glow_row.add_child(_glow_bar)
	col.add_child(glow_row)

	_players_label = Label.new()
	col.add_child(_players_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	_message = Label.new()
	_message.add_theme_font_size_override("font_size", 20)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_message)

	var help := Label.new()
	help.text = "Left-click: place · Right-click: remove your tower · 1–4: pick a tower"
	help.add_theme_color_override("font_color", Color("#B9C2DA"))
	col.add_child(help)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	col.add_child(bar)
	for i in world.TOWER_ORDER.size():
		var t: String = world.TOWER_ORDER[i]
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, world.TOWERS[t].name]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(170, 44)
		b.pressed.connect(func(): world.select_tower(t))
		bar.add_child(b)
		_buttons[t] = b
	set_selected(world.selected_type)

	Net.players_updated.connect(_refresh_players)
	_refresh_players()


func _refresh_players() -> void:
	var names := []
	for n in Net.players.values():
		names.append(n)
	names.sort()
	_players_label.text = "Playing: " + (", ".join(PackedStringArray(names)) if names.size() > 0 else "—")


func set_selected(t: String) -> void:
	for k in _buttons:
		_buttons[k].button_pressed = k == t


func set_glow(v: float) -> void:
	_glow_bar.value = v


func show_message(text: String) -> void:
	_message.text = text
	_message_timer = 3.0


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message.text = ""
