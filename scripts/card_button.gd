extends Button
## A lantern-glow card: metal frame (copper / silver / gold), a picture, a
## name strip, an optional key badge and an optional coin-cost tag hanging
## off the bottom. Used for tower picks in the HUD and hero picks on the
## start screen.

const UI := preload("res://scripts/ui_theme.gd")

var card_size := Vector2(108, 132)
var _halo: TextureRect
var _frame: NinePatchRect
var _picture: TextureRect
var _title: Label
var _sub: Label
var _cost_box: PanelContainer
var _cost: Label
var _selected := false
var _metal := "copper"


func setup(picture: Texture2D, title: String, size := Vector2(108, 132), key := "", subtitle := "") -> void:
	card_size = size
	text = ""
	custom_minimum_size = size + Vector2(0, 26)
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	pivot_offset = size / 2

	_halo = TextureRect.new()
	_halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_halo.texture = UI.tex("card_halo")
	_halo.position = Vector2(-18, -18)
	_halo.size = size + Vector2(36, 36)
	_halo.stretch_mode = TextureRect.STRETCH_SCALE
	_halo.visible = false
	_add(_halo)

	_frame = NinePatchRect.new()
	_frame.size = size
	_frame.patch_margin_left = 20
	_frame.patch_margin_right = 20
	_frame.patch_margin_top = 20
	_frame.patch_margin_bottom = 50
	_add(_frame)

	var strip := (34.0 if size.x >= 90 else 26.0) if subtitle == "" else 50.0
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.texture = picture
	_picture.position = Vector2(14, 12)
	_picture.size = Vector2(size.x - 28, size.y - 12 - strip - 6)
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_add(_picture)

	_title = _text(title, 10 if size.x < 90 else (15 if size.x < 140 else 22), Color.WHITE, true)
	if size.x < 90:
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.clip_text = false
		_title.add_theme_constant_override("line_spacing", -4)
	_title.position = Vector2(9, size.y - 12 - strip)
	_title.size = Vector2(size.x - 18, 30 if subtitle != "" else strip)
	if subtitle != "":
		_sub = _text(subtitle, 15, UI.LILAC, false)
		_sub.position = Vector2(9, size.y - 12 - strip + 26)
		_sub.size = Vector2(size.x - 18, 20)

	if key != "":
		var badge := TextureRect.new()
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.texture = UI.tex("badge")
		badge.position = Vector2(-7, -7)
		badge.size = Vector2(30, 30)
		_add(badge)
		var k := _text(key, 17, UI.INK, true)
		k.position = badge.position + Vector2(0, 1)
		k.size = badge.size
		k.remove_theme_constant_override("outline_size")

	_cost_box = PanelContainer.new()
	_cost_box.theme_type_variation = "Pill"
	_cost_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost_box.visible = false
	_cost_box.resized.connect(_place_cost)
	add_child(_cost_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost_box.add_child(row)
	UI.picture(row, UI.tex("coin"), Vector2(22, 22))
	_cost = UI.label(row, "", 17, UI.GOLD, true, 5)

	set_metal("copper")
	mouse_entered.connect(func(): scale = Vector2(1.04, 1.04))
	mouse_exited.connect(func(): scale = Vector2.ONE)


func _add(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)


func _text(t: String, size: int, color: Color, heading: bool) -> Label:
	var l := UI.label(self, t, size, color, heading, 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	return l


func set_metal(metal: String) -> void:
	_metal = metal
	_frame.texture = UI.tex("card_" + ("gold" if _selected else metal))


func set_selected(on: bool) -> void:
	_selected = on
	_halo.visible = on
	set_metal(_metal)


func set_cost(amount: int, affordable := true) -> void:
	_cost_box.visible = amount >= 0
	_cost.text = str(amount)
	_cost.add_theme_color_override("font_color", UI.GOLD if affordable else UI.CORAL)
	_picture.modulate = Color.WHITE if affordable else Color(0.6, 0.6, 0.7)


func _place_cost() -> void:
	_cost_box.position = Vector2((card_size.x - _cost_box.size.x) / 2, card_size.y - 16)
