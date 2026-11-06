extends CanvasLayer
## In-match HUD for Gumdrop Glade, in the Lanternfall style (see ui_theme.gd).
## Reads the World's state; buttons call the World's client actions. Keys
## mirror every button for quick play.

const D := preload("res://scripts/data.gd")
const UI := preload("res://scripts/ui_theme.gd")
const CardButton := preload("res://scripts/card_button.gd")

var world: Node
var preview_results := false   # test helper: show the results screen now
var _wave_label: Label
var _phase_label: Label
var _glow_bar: ProgressBar
var _glow_pct: Label
var _coins_label: Label
var _team_box: VBoxContainer
var _tower_cards := {}
var _ability_btn: Button
var _ability_icon: TextureRect
var _ready_btn: Button
var _gate_btn: Button
var _panel: PanelContainer
var _panel_card: NinePatchRect
var _panel_icon: TextureRect
var _panel_title: Label
var _panel_flames: HBoxContainer
var _panel_owner: Label
var _panel_info: Label
var _upgrade_btn: Button
var _sell_btn: Button
var _ribbon: PanelContainer
var _ribbon_label: Label
var _message_t := 0.0
var _team_sig := ""
var _results: Control
var _results_title: Label
var _results_sub: Label
var _results_stats: HBoxContainer
var _results_team: GridContainer
var _results_timer: Label
var _results_sig := ""
var _sound_panel: PanelContainer


func setup(w: Node) -> void:
	world = w
	var root := Control.new()
	root.theme = UI.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top_left(root)
	_build_top_right(root)
	_build_ribbon(root)
	_build_bottom(root)
	_build_tower_panel(root)
	_build_results(root)
	refresh()


# ---------------------------------------------------------------- top left
func _build_top_left(root: Control) -> void:
	var p := PanelContainer.new()
	p.position = Vector2(16, 14)
	root.add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)
	UI.picture(row, UI.icon("pip"), Vector2(78, 78))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	UI.label(col, "GUMDROP GLADE", 15, UI.LILAC, true, 4)
	_wave_label = UI.label(col, "", 30, UI.GOLD, true, 8)
	_phase_label = UI.label(col, "", 16, UI.CREAM)
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 6)
	col.add_child(gr)
	UI.picture(gr, UI.tex("flame"), Vector2(24, 24))
	_glow_bar = ProgressBar.new()
	_glow_bar.custom_minimum_size = Vector2(200, 24)
	_glow_bar.max_value = D.PIP_MAX
	_glow_bar.show_percentage = false
	_glow_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gr.add_child(_glow_bar)
	_glow_pct = UI.label(gr, "", 16, Color("#FFE3A3"), true, 4)


# ---------------------------------------------------------------- top right
func _build_top_right(root: Control) -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.position = Vector2(-16, 14)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	var top := HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var snd := UI.button(top, "Sound", "PurpleButton", func(): _sound_panel.visible = not _sound_panel.visible, Vector2(92, 48))
	snd.add_theme_font_size_override("font_size", 16)
	var pill := UI.panel(top, "Pill")
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 8)
	pill.add_child(pr)
	UI.picture(pr, UI.tex("coin"), Vector2(36, 36))
	_coins_label = UI.label(pr, "", 28, UI.GOLD, true, 6)
	_coins_label.custom_minimum_size.x = 64
	_sound_panel = UI.panel(col, "SoftPanel")
	_sound_panel.custom_minimum_size.x = 320
	var sv := VBoxContainer.new()
	_sound_panel.add_child(sv)
	Sfx.make_sliders(sv)
	_sound_panel.visible = false
	var team := UI.panel(col, "SoftPanel")
	team.custom_minimum_size.x = 320
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	team.add_child(tv)
	UI.label(tv, "TEAM", 15, UI.LILAC, true, 4)
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 4)
	tv.add_child(_team_box)


# ---------------------------------------------------------------- ribbon messages
func _build_ribbon(root: Control) -> void:
	_ribbon = PanelContainer.new()
	_ribbon.theme_type_variation = "Ribbon"
	_ribbon.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_ribbon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ribbon.position.y = 18
	_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_ribbon)
	_ribbon_label = UI.label(_ribbon, "", 24, Color.WHITE, true, 8)
	_ribbon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ribbon.visible = false


# ---------------------------------------------------------------- bottom bar
func _build_bottom(root: Control) -> void:
	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -20
	bottom.offset_top = -200
	bottom.offset_bottom = -30
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_END
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 8)
	bottom.add_child(left)
	var help := UI.label(left, "WASD walk · 1–4 pick · click build/select · Q ability · R ready · U upgrade · X sell", 14, UI.LILAC, false, 4)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	left.add_child(cards)
	for i in D.TOWER_ORDER.size():
		var t: String = D.TOWER_ORDER[i]
		var c := CardButton.new()
		cards.add_child(c)
		c.setup(UI.icon(t), D.TOWERS[t].name, Vector2(108, 132), str(i + 1))
		c.tooltip_text = D.TOWERS[t].blurb
		c.pressed.connect(world.select_type.bind(t))
		_tower_cards[t] = c

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(spacer)

	var right := HBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.size_flags_vertical = Control.SIZE_SHRINK_END
	right.add_theme_constant_override("separation", 10)
	bottom.add_child(right)
	_ability_btn = UI.button(right, "", "PurpleButton", world.use_ability, Vector2(200, 76))
	_ability_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ability_icon = TextureRect.new()
	_ability_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ability_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ability_icon.position = Vector2(10, 6)
	_ability_icon.size = Vector2(52, 56)
	_ability_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_btn.add_child(_ability_icon)
	_gate_btn = UI.button(right, "", "Button", world.close_gate, Vector2(160, 76))
	_ready_btn = UI.button(right, "", "GreenButton", world.toggle_ready, Vector2(210, 76))
	_ready_btn.add_theme_font_size_override("font_size", 22)


# ---------------------------------------------------------------- selected tower
func _build_tower_panel(root: Control) -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -20
	_panel.offset_bottom = -126
	_panel.custom_minimum_size = Vector2(380, 0)
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(80, 96)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(holder)
	_panel_card = NinePatchRect.new()
	_panel_card.size = holder.custom_minimum_size
	for side in ["left", "right", "top"]:
		_panel_card.set("patch_margin_" + side, 18)
	_panel_card.patch_margin_bottom = 40
	holder.add_child(_panel_card)
	_panel_icon = TextureRect.new()
	_panel_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel_icon.position = Vector2(10, 8)
	_panel_icon.size = Vector2(60, 66)
	_panel_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	holder.add_child(_panel_icon)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hv)
	_panel_title = UI.label(hv, "", 26, UI.GOLD, true, 7)
	_panel_flames = HBoxContainer.new()
	hv.add_child(_panel_flames)
	_panel_owner = UI.label(hv, "", 15, UI.LILAC)
	_panel_info = UI.label(v, "", 16, UI.CREAM)
	_panel_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_info.custom_minimum_size.x = 340
	var pb := HBoxContainer.new()
	pb.add_theme_constant_override("separation", 10)
	v.add_child(pb)
	_upgrade_btn = UI.button(pb, "", "GoldButton", world.upgrade_selected, Vector2(190, 64))
	_upgrade_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_btn = UI.button(pb, "", "RedButton", world.sell_selected, Vector2(130, 64))
	_panel.visible = false


# ---------------------------------------------------------------- results
func _build_results(root: Control) -> void:
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_results)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.1, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", -26)
	center.add_child(stack)
	var rib := UI.panel(stack, "Ribbon")
	rib.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rib.z_index = 1
	rib.custom_minimum_size.x = 460
	_results_title = UI.label(rib, "", 40, Color.WHITE, true, 10)
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var p := UI.panel(stack)
	p.custom_minimum_size = Vector2(680, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var gap := Control.new()
	gap.custom_minimum_size.y = 22
	v.add_child(gap)
	_results_sub = UI.label(v, "", 20, UI.CREAM)
	_results_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_stats = HBoxContainer.new()
	_results_stats.alignment = BoxContainer.ALIGNMENT_CENTER
	_results_stats.add_theme_constant_override("separation", 14)
	v.add_child(_results_stats)
	var tl := UI.label(v, "YOUR TEAM", 18, UI.LILAC, true, 5)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_team = GridContainer.new()
	_results_team.columns = 4
	_results_team.add_theme_constant_override("h_separation", 12)
	_results_team.add_theme_constant_override("v_separation", 12)
	_results_team.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_results_team)
	_results_timer = UI.label(v, "", 17, UI.LILAC)
	_results_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results.visible = false


func _stat_tile(parent: Node, picture: Texture2D, value: String, caption: String) -> void:
	var t := UI.panel(parent, "Tile")
	t.custom_minimum_size = Vector2(150, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	t.add_child(v)
	var pic := UI.picture(v, picture, Vector2(48, 48))
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var a := UI.label(v, value, 28, Color.WHITE, true, 7)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := UI.label(v, caption, 14, Color("#DCE2FF"), false, 4)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


# ================================================================ updates

func refresh() -> void:
	if world == null or _wave_label == null:
		return
	var me: String = Net.my_name
	var hero: String = world.hero_choice.get(me, Net.my_hero)
	_coins_label.text = str(world.my_coins())
	var w: int = world.wave
	if world.phase == "build":
		var next: int = w + 1
		_wave_label.text = "BOSS NEXT!" if next == D.BOSS_WAVE else "WAVE %d / %d" % [next, D.LAST_WAVE]
	else:
		_wave_label.text = "BIG SHELLBACK!" if w == D.BOSS_WAVE else "WAVE %d / %d" % [w, D.LAST_WAVE]
	for t in _tower_cards:
		var c = _tower_cards[t]
		var cost: int = world.build_cost(me, t)
		c.set_cost(cost, world.my_coins() >= cost)
		c.set_selected(t == world.selected_type and world.selected_cell == null)
	var cd: float = world.hero_cd.get(me, 0.0)
	var h: Dictionary = D.HEROES[hero]
	_ability_icon.texture = UI.icon(hero)
	_ability_btn.text = "Q  %s\n%s" % [h.ability, "Ready!" if cd <= 0.0 else "%ds" % ceili(cd)]
	_ability_btn.disabled = cd > 0.0
	_ability_btn.tooltip_text = h.ability_text
	var r: int = int(world.rush.get(me, 0))
	if r > 0:
		_ability_btn.text = "Q  %s\n%d cheap left" % [h.ability, r]
	if world.gate_closed_waves > 0:
		_gate_btn.text = "Gate closed\n%d wave%s" % [world.gate_closed_waves, "" if world.gate_closed_waves == 1 else "s"]
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
		_ready_btn.text = "Waiting…" if am_ready else "R  READY!\n+%d bonus" % bonus
		_ready_btn.disabled = false
	else:
		_ready_btn.text = "Defend!"
		_ready_btn.disabled = true
	_refresh_team()
	_refresh_panel()
	_refresh_results()


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
			row.add_theme_constant_override("separation", 6)
			var pic := UI.picture(row, null, Vector2(34, 34))
			pic.name = "Pic"
			var nl := UI.label(row, n, 18, Color.WHITE, true, 5)
			nl.custom_minimum_size.x = 96
			nl.clip_text = true
			UI.picture(row, UI.tex("coin"), Vector2(20, 20))
			var cl := UI.label(row, "", 17, UI.GOLD, true, 4)
			cl.name = "Coins"
			cl.custom_minimum_size.x = 44
			var rl := UI.label(row, "", 15, UI.MINT, true, 4)
			rl.name = "Ready"
			rl.custom_minimum_size.x = 54
			if n != Net.my_name:
				var g := UI.button(row, "Gift %d" % D.GIFT_STEP, "GoldButton", world.gift_to.bind(n), Vector2(84, 40))
				g.add_theme_font_size_override("font_size", 15)
			_team_box.add_child(row)
	for row in _team_box.get_children():
		var n: String = row.name.substr(4)
		if row.get_node_or_null("Coins") == null:
			continue
		var hero: String = world.hero_choice.get(n, "bramble")
		(row.get_node("Pic") as TextureRect).texture = UI.icon(hero)
		(row.get_node("Coins") as Label).text = str(int(world.coins.get(n, 0)))
		(row.get_node("Ready") as Label).text = "READY" if world.ready_names.has(n) and world.phase == "build" else ""


func _refresh_panel() -> void:
	var c = world.selected_cell
	if c == null or not world.towers.has(c):
		_panel.visible = false
		return
	_panel.visible = true
	var t: Dictionary = world.towers[c]
	var d: Dictionary = D.TOWERS[t.type]
	var mine: bool = t.owner == Net.my_name
	_panel_card.texture = UI.tex("card_" + UI.metal_for_tier(t.tier))
	_panel_icon.texture = UI.icon(t.type)
	_panel_title.text = d.name
	for ch in _panel_flames.get_children():
		ch.queue_free()
	if d.kind != "wall":
		UI.tier_flames(_panel_flames, t.tier, 22)
		UI.label(_panel_flames, "  Tier %d" % t.tier, 15, Color("#FFE3A3"), true, 4)
	_panel_owner.text = "Built by %s" % t.owner
	var lines := [d.blurb]
	if d.kind != "wall":
		var i: int = t.tier - 1
		lines.append("Damage %s · Range %.1f · %.1f shots/s" % [str(d.damage[i]), world.tower_range(c), d.rate[i]])
	for combo in D.COMBOS:
		if combo.id in world.combos.get(c, []) and (combo.a == t.type or combo.b == t.type):
			lines.append("Combo %s: %s" % [combo.name, combo.text])
	if world.in_glow(c) and d.kind != "wall":
		lines.append("In Pip's glow: fires 10% faster")
	if t.oc > 0.0:
		lines.append("Overcharged!")
	_panel_info.text = "\n".join(PackedStringArray(lines))
	var cost: int = world.upgrade_cost(Net.my_name, c)
	_upgrade_btn.visible = mine and d.kind != "wall"
	_upgrade_btn.text = "Max tier" if cost < 0 else "U  Upgrade\n%d coins" % cost
	_upgrade_btn.disabled = cost < 0 or world.my_coins() < cost
	_sell_btn.visible = mine
	_sell_btn.text = "X  Sell\n+%d" % world.sell_value(c)


func _refresh_results() -> void:
	var show: bool = world.phase == "victory" or world.phase == "defeat" or preview_results
	_results.visible = show
	if not show:
		_results_sig = ""
		return
	var won: bool = world.phase != "defeat"
	var names: Array = world.coins.keys()
	names.sort()
	var built := {}
	for c in world.towers:
		var o: String = world.towers[c].owner
		built[o] = built.get(o, 0) + 1
	var sig := "%s|%d|%d|%s|%s" % [won, world.wave, int(world.glow), str(names), str(built)]
	if sig == _results_sig:
		return
	_results_sig = sig
	_results_title.text = "VICTORY!" if won else "LIGHTS OUT…"
	_results_sub.text = "Pip is safe and glowing bright!" if won else "The Snuffers dimmed Pip's light. Try again!"
	for ch in _results_stats.get_children():
		ch.queue_free()
	for ch in _results_team.get_children():
		ch.queue_free()
	var waves: int = world.wave if won else maxi(world.wave - 1, 0)
	_stat_tile(_results_stats, UI.tex("flame"), "%d" % waves, "waves held")
	_stat_tile(_results_stats, UI.icon("pip"), "%d%%" % int(world.glow), "Pip's glow left")
	_stat_tile(_results_stats, UI.icon("pebble_popper"), "%d" % world.towers.size(), "towers standing")
	for n in names:
		var t := UI.panel(_results_team, "Tile")
		t.custom_minimum_size = Vector2(140, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		t.add_child(v)
		var pic := UI.picture(v, UI.icon(world.hero_choice.get(n, "bramble")), Vector2(56, 56))
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var a := UI.label(v, n, 20, Color.WHITE, true, 6)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		a.clip_text = true
		var b := UI.label(v, "%d towers" % built.get(n, 0), 14, Color("#DCE2FF"), false, 4)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func show_message(text: String) -> void:
	_ribbon_label.text = text
	_ribbon.visible = text != ""
	_ribbon.reset_size()
	_message_t = 3.5


func _process(delta: float) -> void:
	if world == null:
		return
	_glow_bar.value = world.glow
	_glow_pct.text = "%d%%" % int(world.glow)
	if world.phase == "build":
		world.phase_timer = maxf(0.0, world.phase_timer - delta) if not multiplayer.is_server() else world.phase_timer
		_phase_label.text = "Build time · next wave in %ds" % ceili(world.phase_timer)
	elif world.phase == "wave":
		_phase_label.text = "Defend Pip!"
	else:
		_phase_label.text = "New match in %ds" % ceili(maxf(world.phase_timer, 0.0))
	_results_timer.text = "A new match starts in %ds" % ceili(maxf(world.phase_timer, 0.0))
	if _message_t > 0.0:
		_message_t -= delta
		if _message_t <= 0.0:
			_ribbon.visible = false
