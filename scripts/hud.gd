extends CanvasLayer
## In-match HUD for Gumdrop Glade. Reads the World's state; buttons call the
## World's client actions. Keys mirror every button for quick play.

const D := preload("res://scripts/data.gd")

var world: Node
var _wave_label: Label
var _phase_label: Label
var _glow_bar: ProgressBar
var _coins_label: Label
var _team_box: VBoxContainer
var _tower_buttons := {}
var _ability_btn: Button
var _ready_btn: Button
var _gate_btn: Button
var _panel: PanelContainer
var _panel_title: Label
var _panel_info: Label
var _upgrade_btn: Button
var _sell_btn: Button
var _message: Label
var _banner: Label
var _message_t := 0.0
var _team_sig := ""


func setup(w: Node) -> void:
	world = w
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# top-left: map, wave, phase, Pip's glow
	var tl := _panel_box(root, Control.PRESET_TOP_LEFT, Vector2(16, 16))
	var title := _label(tl, "GUMDROP GLADE", 22, Color("#FFC44D"))
	title.uppercase = true
	_wave_label = _label(tl, "", 20, Color.WHITE)
	_phase_label = _label(tl, "", 16, Color("#D9D2F2"))
	var gr := HBoxContainer.new()
	tl.add_child(gr)
	_label(gr, "Pip's glow", 16, Color("#FFE3A3"))
	_glow_bar = ProgressBar.new()
	_glow_bar.custom_minimum_size = Vector2(200, 18)
	_glow_bar.max_value = D.PIP_MAX
	_glow_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#FFC44D")
	fill.set_corner_radius_all(6)
	_glow_bar.add_theme_stylebox_override("fill", fill)
	gr.add_child(_glow_bar)

	# top-right: coins and team
	var top_right := _panel_box(root, Control.PRESET_TOP_RIGHT, Vector2(-16, 16))
	_coins_label = _label(top_right, "", 26, Color("#FFD34D"))
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(top_right, "Team", 14, Color("#B9A8E8"))
	_team_box = VBoxContainer.new()
	top_right.add_child(_team_box)

	# bottom bar
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -132
	bottom.offset_bottom = -12
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	_message = _label(bottom, "", 22, Color.WHITE)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_constant_override("outline_size", 6)
	_message.add_theme_color_override("font_outline_color", Color("#1B1638"))
	var help := _label(bottom, "WASD walk · 1–4 pick tower · click to build or select · Q ability · R ready · U upgrade · X sell", 14, Color("#D9D2F2"))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bottom.add_child(row)
	for i in D.TOWER_ORDER.size():
		var t: String = D.TOWER_ORDER[i]
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 52)
		b.pressed.connect(world.select_type.bind(t))
		b.tooltip_text = D.TOWERS[t].blurb
		row.add_child(b)
		_tower_buttons[t] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_ability_btn = _button(row, "", world.use_ability, 190)
	_gate_btn = _button(row, "", world.close_gate, 170)
	_ready_btn = _button(row, "", world.toggle_ready, 190)

	# selected tower panel (above the bottom bar, right)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -300
	_panel.offset_right = -16
	_panel.offset_top = -330
	_panel.offset_bottom = -150
	_panel.add_theme_stylebox_override("panel", _box_style())
	root.add_child(_panel)
	var pv := VBoxContainer.new()
	_panel.add_child(pv)
	_panel_title = _label(pv, "", 20, Color("#FFC44D"))
	_panel_info = _label(pv, "", 15, Color("#E8E2F8"))
	_panel_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pb := HBoxContainer.new()
	pv.add_child(pb)
	_upgrade_btn = _button(pb, "", world.upgrade_selected, 130)
	_sell_btn = _button(pb, "", world.sell_selected, 120)
	_panel.visible = false

	_banner = _label(root, "", 54, Color("#FFC44D"))
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.add_theme_color_override("font_outline_color", Color("#1B1638"))
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.visible = false
	refresh()


func _box_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.08, 0.2, 0.78)
	s.set_corner_radius_all(12)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _panel_box(root: Control, preset: int, at: Vector2) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box_style())
	p.set_anchors_preset(preset)
	if preset == Control.PRESET_TOP_RIGHT:
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.position = at
	root.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	return v


func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, action: Callable, width: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 52)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


# ================================================================ updates

func refresh() -> void:
	if world == null or _wave_label == null:
		return
	var me: String = Net.my_name
	var hero: String = world.hero_choice.get(me, Net.my_hero)
	_coins_label.text = "%d coins" % world.my_coins()
	if world.phase == "victory" or world.phase == "defeat":
		_banner.visible = true
		_banner.text = "Victory! Pip is safe!" if world.phase == "victory" else "Pip's light went out…"
	else:
		_banner.visible = false
	var w: int = world.wave
	if world.phase == "build":
		var next: int = w + 1
		_wave_label.text = "Next: Big Shellback!" if next == D.BOSS_WAVE else "Next: wave %d of %d" % [next, D.LAST_WAVE]
	else:
		_wave_label.text = "Big Shellback!" if w == D.BOSS_WAVE else "Wave %d of %d" % [w, D.LAST_WAVE]
	for t in _tower_buttons:
		var b: Button = _tower_buttons[t]
		b.text = "%d %s\n%d coins" % [D.TOWER_ORDER.find(t) + 1, D.TOWERS[t].name, world.build_cost(me, t)]
		b.button_pressed = (t == world.selected_type and world.selected_cell == null)
	var cd: float = world.hero_cd.get(me, 0.0)
	var h: Dictionary = D.HEROES[hero]
	_ability_btn.text = "Q  %s\n%s" % [h.ability, "ready" if cd <= 0.0 else "%ds" % ceili(cd)]
	_ability_btn.disabled = cd > 0.0
	_ability_btn.tooltip_text = h.ability_text
	var r: int = int(world.rush.get(me, 0))
	if r > 0:
		_ability_btn.text += " · %d cheap left" % r
	if world.gate_closed_waves > 0:
		_gate_btn.text = "Gate closed\n%d wave%s left" % [world.gate_closed_waves, "" if world.gate_closed_waves == 1 else "s"]
		_gate_btn.disabled = true
	elif world.gate_cooldown > 0:
		_gate_btn.text = "Gate resting\n%d wave%s" % [world.gate_cooldown, "" if world.gate_cooldown == 1 else "s"]
		_gate_btn.disabled = true
	else:
		_gate_btn.text = "Close gate\n%d coins" % D.GATE_COST
		_gate_btn.disabled = world.phase != "build"
	var am_ready: bool = world.ready_names.has(me)
	if world.phase == "build":
		var bonus := int(world.phase_timer) * D.EARLY_CALL_PER_SECOND
		_ready_btn.text = ("R  Waiting for team…" if am_ready else "R  Ready!\n+%d early bonus" % bonus)
		_ready_btn.disabled = false
	else:
		_ready_btn.text = "Wave in progress"
		_ready_btn.disabled = true
	_refresh_team()
	_refresh_panel()


func _refresh_team() -> void:
	var names: Array = world.coins.keys()
	names = names.filter(func(n): return n in Net.players.values())
	names.sort()
	var sig := ",".join(PackedStringArray(names))
	if sig != _team_sig:
		_team_sig = sig
		for ch in _team_box.get_children():
			ch.queue_free()
		for n in names:
			var row := HBoxContainer.new()
			row.name = "Row_" + n
			var l := _label(row, "", 16, Color.WHITE)
			l.name = "Info"
			l.custom_minimum_size.x = 230
			if n != Net.my_name:
				var g := Button.new()
				g.text = "Gift %d" % D.GIFT_STEP
				g.pressed.connect(world.gift_to.bind(n))
				row.add_child(g)
			_team_box.add_child(row)
	for row in _team_box.get_children():
		var n: String = row.name.substr(4)
		var info: Label = row.get_node_or_null("Info")
		if info == null:
			continue
		var hero: String = world.hero_choice.get(n, "bramble")
		var mark := "  ✓ ready" if world.ready_names.has(n) and world.phase == "build" else ""
		info.text = "%s (%s) · %d%s" % [n, D.HEROES[hero].name, int(world.coins.get(n, 0)), mark]


func _refresh_panel() -> void:
	var c = world.selected_cell
	if c == null or not world.towers.has(c):
		_panel.visible = false
		return
	_panel.visible = true
	var t: Dictionary = world.towers[c]
	var d: Dictionary = D.TOWERS[t.type]
	var mine: bool = t.owner == Net.my_name
	_panel_title.text = "%s%s" % [d.name, "" if d.kind == "wall" else "  · tier %d" % t.tier]
	var lines := ["Built by %s" % t.owner, d.blurb]
	if d.kind != "wall":
		var i: int = t.tier - 1
		lines.append("Damage %s · range %.1f · %.1f shots/s" % [str(d.damage[i]), world.tower_range(c), d.rate[i]])
	for combo in D.COMBOS:
		if combo.id in world.combos.get(c, []) and (combo.a == t.type or combo.b == t.type):
			lines.append("Combo: %s — %s" % [combo.name, combo.text])
	if world.in_glow(c) and d.kind != "wall":
		lines.append("In Pip's glow: fires 10% faster")
	if t.oc > 0.0:
		lines.append("Overcharged!")
	_panel_info.text = "\n".join(PackedStringArray(lines))
	var cost: int = world.upgrade_cost(Net.my_name, c)
	_upgrade_btn.visible = mine and d.kind != "wall"
	_upgrade_btn.text = "U  Max tier" if cost < 0 else "U  Upgrade\n%d coins" % cost
	_upgrade_btn.disabled = cost < 0 or world.my_coins() < cost
	_sell_btn.visible = mine
	_sell_btn.text = "X  Sell\n+%d" % world.sell_value(c)


func show_message(text: String) -> void:
	_message.text = text
	_message_t = 3.5


func _process(delta: float) -> void:
	if world == null:
		return
	_glow_bar.value = world.glow
	if world.phase == "build":
		world.phase_timer = maxf(0.0, world.phase_timer - delta) if not multiplayer.is_server() else world.phase_timer
		_phase_label.text = "Build time · next wave in %ds" % ceili(world.phase_timer)
	elif world.phase == "wave":
		_phase_label.text = "Defend Pip!"
	else:
		_phase_label.text = "New match in %ds" % ceili(maxf(world.phase_timer, 0.0))
	if _message_t > 0.0:
		_message_t -= delta
		if _message_t <= 0.0:
			_message.text = ""
