extends RefCounted
## Lanternfall's look: chunky outlined buttons, brass lantern-frame panels,
## lantern-glow cards and a swallowtail ribbon. Textures come from
## art/tools/make_ui.py (assets/ui/). Fonts: Lilita One (headings) and
## Fredoka (everything else), both SIL Open Font License.
##
## Button styles: "Button" (blue) plus the variations GoldButton, GreenButton,
## PurpleButton, RedButton. Panels: "PanelContainer" (brass), SoftPanel, Pill,
## Ribbon. Labels: Heading, Title.

const UI := "res://assets/ui/"
const INK := Color("#120E2B")
const GOLD := Color("#FFC44D")
const CREAM := Color("#F6F0FF")
const LILAC := Color("#C9BEF0")
const MINT := Color("#7CF29A")
const CORAL := Color("#FF8B7A")

static var _theme: Theme
static var _heading: Font
static var _body: Font
static var _textures := {}


static func tex(name: String) -> Texture2D:
	if not _textures.has(name):
		var path := UI + name + ".png"
		_textures[name] = load(path) if ResourceLoader.exists(path) else null
	return _textures[name]


static func icon(id: String) -> Texture2D:
	return tex("icons/" + id)


static func heading_font() -> Font:
	if _heading == null:
		_heading = load("res://assets/fonts/LilitaOne-Regular.ttf")
	return _heading


static func body_font() -> Font:
	if _body == null:
		var v := FontVariation.new()
		v.base_font = load("res://assets/fonts/Fredoka-Variable.ttf")
		v.variation_opentype = {"wght": 560}
		_body = v
	return _body


## A 9-slice box. margins = texture slice (l, t, r, b); pad = content padding.
static func box(name: String, margins: Vector4, pad: Vector4) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex(name)
	s.texture_margin_left = margins.x
	s.texture_margin_top = margins.y
	s.texture_margin_right = margins.z
	s.texture_margin_bottom = margins.w
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 18

	# ---- buttons
	_button_type(t, "Button", "blue")
	for v in [["GoldButton", "gold"], ["GreenButton", "green"], ["PurpleButton", "purple"], ["RedButton", "red"]]:
		t.set_type_variation(v[0], "Button")
		_button_type(t, v[0], v[1])

	# ---- panels
	t.set_stylebox("panel", "PanelContainer", box("panel_brass", Vector4(24, 24, 24, 27), Vector4(20, 16, 20, 18)))
	t.set_stylebox("panel", "Panel", box("panel_brass", Vector4(24, 24, 24, 27), Vector4(20, 16, 20, 18)))
	t.set_type_variation("SoftPanel", "PanelContainer")
	t.set_stylebox("panel", "SoftPanel", box("panel_soft", Vector4(14, 14, 14, 14), Vector4(12, 8, 12, 8)))
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", box("pill", Vector4(22, 20, 22, 20), Vector4(10, 4, 20, 4)))
	t.set_type_variation("Ribbon", "PanelContainer")
	t.set_stylebox("panel", "Ribbon", box("ribbon", Vector4(50, 22, 50, 26), Vector4(60, 8, 60, 20)))
	t.set_type_variation("Tile", "PanelContainer")
	t.set_stylebox("panel", "Tile", box("tile", Vector4(16, 16, 16, 19), Vector4(10, 8, 10, 12)))
	t.set_stylebox("panel", "TooltipPanel", box("panel_soft", Vector4(14, 14, 14, 14), Vector4(12, 8, 12, 8)))

	# ---- labels
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", INK)
	t.set_type_variation("Heading", "Label")
	t.set_font("font", "Heading", heading_font())
	t.set_font_size("font_size", "Heading", 28)
	t.set_color("font_color", "Heading", GOLD)
	t.set_constant("outline_size", "Heading", 8)
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", heading_font())
	t.set_font_size("font_size", "Title", 34)
	t.set_color("font_color", "Title", Color.WHITE)
	t.set_constant("outline_size", "Title", 10)
	t.set_color("font_color", "TooltipLabel", CREAM)

	# ---- progress bar (Pip's glow)
	t.set_stylebox("background", "ProgressBar", box("bar_bg", Vector4(12, 11, 12, 11), Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", box("bar_fill", Vector4(12, 11, 12, 11), Vector4(0, 0, 0, 0)))

	# ---- text fields
	var field := StyleBoxFlat.new()
	field.bg_color = Color("#0E1230")
	field.border_color = Color("#4D58A8")
	field.set_border_width_all(3)
	field.set_corner_radius_all(12)
	field.content_margin_left = 14
	field.content_margin_right = 14
	field.content_margin_top = 8
	field.content_margin_bottom = 8
	var focus := field.duplicate() as StyleBoxFlat
	focus.border_color = GOLD
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color("#6E78A8"))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_font_size("font_size", "LineEdit", 20)
	_theme = t
	return t


static func _button_type(t: Theme, type: String, color: String) -> void:
	var m := Vector4(20, 20, 20, 24)
	t.set_stylebox("normal", type, box("btn_%s_normal" % color, m, Vector4(16, 7, 16, 15)))
	t.set_stylebox("hover", type, box("btn_%s_hover" % color, m, Vector4(16, 7, 16, 15)))
	t.set_stylebox("pressed", type, box("btn_%s_pressed" % color, m, Vector4(16, 12, 16, 10)))
	t.set_stylebox("hover_pressed", type, box("btn_%s_pressed" % color, m, Vector4(16, 12, 16, 10)))
	t.set_stylebox("disabled", type, box("btn_gray_normal", m, Vector4(16, 7, 16, 15)))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_font("font", type, heading_font())
	t.set_font_size("font_size", type, 19)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, type, Color.WHITE)
	t.set_color("font_disabled_color", type, Color("#D5D8E6"))
	t.set_color("font_outline_color", type, INK)
	t.set_constant("outline_size", type, 6)


# ------------------------------------------------------------------ helpers

static func label(parent: Node, text: String, size := 18, color := CREAM, heading := false, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	if heading:
		l.add_theme_font_override("font", heading_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func picture(parent: Node, texture: Texture2D, size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


static func button(parent: Node, text: String, variation: String, action: Callable, size := Vector2(140, 60)) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = size
	if action.is_valid():
		b.pressed.connect(action)
	parent.add_child(b)
	return b


static func panel(parent: Node, variation := "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	parent.add_child(p)
	return p


## Little flame pips that show a tower's tier (lit) out of 3.
static func tier_flames(parent: Node, tier: int, size := 22) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	for i in 3:
		var f := picture(h, tex("flame"), Vector2(size, size))
		f.modulate = Color.WHITE if i < tier else Color(0.25, 0.25, 0.4, 0.8)
	return h


static func metal_for_tier(tier: int) -> String:
	return ["copper", "silver", "gold"][clampi(tier - 1, 0, 2)]
