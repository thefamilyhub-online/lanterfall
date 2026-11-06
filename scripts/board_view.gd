extends Node3D
## Everything the player sees on Gumdrop Glade. Reads state from the World,
## never changes it. Models load from res://assets/... and fall back to simple
## shapes when a model file is missing, so the game always runs.

const D := preload("res://scripts/data.gd")
const GladeDecor := preload("res://scripts/glade_decor.gd")
const ForestDecor := preload("res://scripts/tanglewood_decor.gd")
const Shapes := preload("res://scripts/shapes.gd")

const SNUFFER_COLORS := {
	"scamper": Color("#7B5BD6"), "shellback": Color("#5E7FA6"),
	"flutter": Color("#E06FB0"), "big_shellback": Color("#4E6A93"),
}
const HERO_COLORS := {"bramble": Color("#4FA44F"), "glint": Color("#F5B83D")}
const PATH_COLORS := [Color("#F5B83D"), Color("#F27BAA"), Color("#7FD3FF")]

var world: Node
var camera: Camera3D

var _mats := {}
var _models := {}
var _tower_nodes := {}
var _snuffers := {}          # id -> {node, target, type, hp_fg, ring, ice, wings}
var _heroes := {}            # name -> {node, target}
var _links: Array[Node3D] = []
var _path_dots: Array[Node3D] = []
var _hover: MeshInstance3D
var _range_ring: MeshInstance3D
var _reach_ring: MeshInstance3D
var _glow_ring: MeshInstance3D
var _pip: Node3D
var _pip_light: OmniLight3D
var _gate_bars: Array[Node3D] = []
var _time := 0.0
var _shake := 0.0
var _flinch := 0.0
var _flash_amt := 0.0
var _cam_base := Vector3.ZERO
var _last_glow := -1.0
var _coin_mesh: CylinderMesh
var _coin_mat: StandardMaterial3D
var _flash: ColorRect


func setup(w: Node) -> void:
	world = w
	_build_environment()
	_build_board()
	_build_landmarks()
	_build_helpers()
	refresh_paths()


# ================================================================ assets

func mat(color: Color, emit := 0.0, alpha := 1.0, unshaded := false) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(), emit, alpha, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = 0.65
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


func model(path: String) -> Node3D:
	if not _models.has(path):
		_models[path] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _models[path]
	return scene.instantiate() if scene else null


func mesh_node(mesh: Mesh, material: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	return m


func sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func ring(radius: float, thickness: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = radius - thickness
	t.outer_radius = radius
	t.rings = 48
	return t


# ================================================================ scene

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#6FB26A")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#B9A8E8")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.08
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_energy = 1.15
	sun.light_color = Color("#FFF1DD")
	if D.MAP.theme == "forest":
		# dusk in the woods: warm low sun, cooler ambient, lanterns do the rest
		sun.rotation_degrees = Vector3(-38, -40, 0)
		sun.light_energy = 0.85
		sun.light_color = Color("#FFC890")
		e.ambient_light_color = Color("#8FA0E0")
		e.ambient_light_energy = 0.5
		e.background_color = Color("#2E4A33")
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 40
	add_child(camera)
	camera.position = Vector3(0.6, 20.5, 13.2)
	camera.look_at(Vector3(0.6, 0, 1.9))
	_cam_base = camera.position
	# a soft warm flash around the screen edges when Pip gets hit
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform float amount = 0.0;\nvoid fragment() {\n\tvec2 p = UV - 0.5;\n\tfloat v = smoothstep(0.25, 0.75, length(p * vec2(1.0, 1.3)));\n\tCOLOR = vec4(1.0, 0.45, 0.35, v * amount * 0.6);\n}"
	var smat := ShaderMaterial.new()
	smat.shader = sh
	_flash.material = smat
	layer.add_child(_flash)


func _build_board() -> void:
	var decor: Node3D = ForestDecor.new() if D.MAP.theme == "forest" else GladeDecor.new()
	decor.name = "MapDecor"
	add_child(decor)
	decor.build(self)
	var colors := [Color("#F27BAA"), Color("#FFD34D"), Color("#7FC8F0"), Color("#B48CF2")]
	var i := 0
	for r in D.MAP.rocks:
		var node: Node3D = Shapes.stump() if D.MAP.theme == "forest" else model("res://assets/props/gumdrop.glb")
		if node == null:
			node = mesh_node(sphere(0.42), mat(colors[i % colors.size()]))
			node.scale = Vector3(1, 0.8, 1)
		node.position = world.cell_to_world(r)
		node.rotation.y = i * 1.3
		add_child(node)
		i += 1
	for t in D.MAP.trees:
		var tree := model("res://assets/props/lollipop_tree.glb")
		if tree == null:
			tree = Node3D.new()
			var stick := CylinderMesh.new()
			stick.top_radius = 0.06
			stick.bottom_radius = 0.06
			stick.height = 1.6
			tree.add_child(mesh_node(stick, mat(Color("#F7F2E8")), Vector3(0, 0.8, 0)))
			tree.add_child(mesh_node(sphere(0.6), mat(colors[i % colors.size()]), Vector3(0, 1.8, 0)))
		tree.position = Vector3(t.x - world.W / 2.0, -0.65, t.y - world.H / 2.0)
		tree.scale = Vector3.ONE * 1.3
		add_child(tree)
		i += 1


func _build_landmarks() -> void:
	for k in D.MAP.entrances.size():
		var e: Vector2i = D.MAP.entrances[k]
		var gate := model("res://assets/props/waygate.glb")
		if gate == null:
			gate = mesh_node(ring(0.55, 0.14), mat(Color("#8C5BD6"), 1.5))
			gate.rotation.z = PI / 2
			gate.position.y = 0.55
		var holder := Node3D.new()
		holder.position = world.cell_to_world(e) + Vector3(-0.55, 0, 0)
		holder.rotation.y = PI / 2
		holder.add_child(gate)
		add_child(holder)
		if k in D.MAP.gates:
			var lg := model("res://assets/props/licorice_gate.glb")
			var gh := Node3D.new()
			gh.position = world.cell_to_world(e) + Vector3(0.25, 0, 0)
			gh.rotation.y = PI / 2
			var bars: Node3D = null
			if lg:
				gh.add_child(lg)
				bars = lg.find_child("Bars*", true, false) as Node3D
			if bars == null:
				bars = Node3D.new()
				var bar_color := Color("#2B1B2E") if D.MAP.theme == "candy" else Color("#3E6B2E")
				for j in 4:
					var bar := BoxMesh.new()
					bar.size = Vector3(0.09, 0.9, 0.09)
					bars.add_child(mesh_node(bar, mat(bar_color), Vector3(-0.33 + j * 0.22, 0.45, 0)))
				gh.add_child(bars)
			_gate_bars.append(bars)
			add_child(gh)
	_pip = Node3D.new()
	_pip.position = world.cell_to_world(D.MAP.pip)
	var pip_model := model("res://assets/pip/pip.glb")
	if pip_model == null:
		pip_model = mesh_node(sphere(0.4), mat(Color("#FFC44D"), 2.5), Vector3(0, 0.5, 0))
	_pip.add_child(pip_model)
	add_child(_pip)
	_pip_light = OmniLight3D.new()
	_pip_light.light_color = Color("#FFC44D")
	_pip_light.position = _pip.position + Vector3(0, 1.0, 0)
	_pip_light.light_energy = 3.0
	_pip_light.omni_range = 7.0
	add_child(_pip_light)
	_glow_ring = mesh_node(ring(1.0, 0.03), mat(Color("#FFC44D"), 1.5, 0.55, true), _pip.position + Vector3(0, 0.03, 0))
	add_child(_glow_ring)


func _build_helpers() -> void:
	var hm := BoxMesh.new()
	hm.size = Vector3(0.96, 0.04, 0.96)
	_hover = mesh_node(hm, StandardMaterial3D.new())
	var hmat: StandardMaterial3D = _hover.material_override
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(_hover)
	_range_ring = mesh_node(ring(1.0, 0.03), mat(Color("#FFFFFF"), 0.0, 0.7, true))
	_range_ring.visible = false
	add_child(_range_ring)
	_reach_ring = mesh_node(ring(D.BUILD_REACH + 0.5, 0.04), mat(Color("#7FE3F0"), 0.0, 0.45, true))
	add_child(_reach_ring)


# ================================================================ paths, gate

func refresh_paths() -> void:
	for d in _path_dots:
		d.queue_free()
	_path_dots.clear()
	var dot := sphere(0.06)
	for k in D.MAP.entrances.size():
		if k in D.MAP.gates and world.gate_closed_waves > 0:
			continue
		var path: Array[Vector2i] = world.path_from(D.MAP.entrances[k])
		for i in range(1, path.size() - 1):
			var n := mesh_node(dot, mat(PATH_COLORS[k], 1.0), world.cell_to_world(path[i]) + Vector3(0.12 * (k - (D.MAP.entrances.size() - 1) / 2.0), 0.09, 0))
			add_child(n)
			_path_dots.append(n)


func refresh_gate() -> void:
	var closed: bool = world.gate_closed_waves > 0
	var changed := false
	for bars in _gate_bars:
		if bars.visible != closed:
			bars.visible = closed
			changed = true
	if changed:
		refresh_paths()


# ================================================================ towers

func rebuild_towers() -> void:
	for c in _tower_nodes:
		_tower_nodes[c].queue_free()
	_tower_nodes.clear()
	for c in world.towers:
		add_tower(c)
	refresh_links()
	refresh_paths()


func add_tower(c: Vector2i) -> void:
	if _tower_nodes.has(c):
		return
	var t: Dictionary = world.towers[c]
	var root := Node3D.new()
	root.position = world.cell_to_world(c)
	var m := model("res://assets/towers/%s.glb" % t.type)
	if m == null:
		m = Shapes.tower(t.type)
	if m == null:
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 0.8, 0.8)
		m = mesh_node(box, mat(Color("#888888")), Vector3(0, 0.4, 0))
	m.name = "Model"
	root.add_child(m)
	var label := Label3D.new()
	label.text = t.owner
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.font_size = 44
	label.outline_size = 12
	label.position.y = 2.15
	label.modulate = Color(1, 1, 1, 0.85)
	root.add_child(label)
	var pips := Node3D.new()
	pips.name = "Tier"
	root.add_child(pips)
	var spark := mesh_node(ring(0.55, 0.05), mat(Color("#FFE680"), 3.0, 0.9, true), Vector3(0, 1.2, 0))
	spark.name = "Overcharge"
	spark.visible = false
	root.add_child(spark)
	var jam := Node3D.new()
	jam.name = "Jam"
	jam.visible = false
	for k in 3:
		var bolt := mesh_node(BoxMesh.new(), mat(Color("#FFB627"), 3.0), Vector3(cos(k * 2.1) * 0.3, 1.35 + k * 0.05, sin(k * 2.1) * 0.3))
		bolt.scale = Vector3(0.05, 0.22, 0.05)
		bolt.rotation.z = 0.6 * (1 if k % 2 == 0 else -1)
		jam.add_child(bolt)
	root.add_child(jam)
	add_child(root)
	_tower_nodes[c] = root
	update_tower(c)
	_pop_in(root)


func update_tower(c: Vector2i) -> void:
	if not _tower_nodes.has(c) or not world.towers.has(c):
		return
	var root: Node3D = _tower_nodes[c]
	var tier: int = world.towers[c].tier
	root.get_node("Model").scale = Vector3.ONE * (0.88 + 0.07 * (tier - 1))
	var pips: Node3D = root.get_node("Tier")
	for ch in pips.get_children():
		ch.queue_free()
	if D.TOWERS[world.towers[c].type].kind != "wall":
		for i in tier:
			pips.add_child(mesh_node(sphere(0.06), mat(Color("#FFC44D"), 2.0), Vector3(-0.42 + i * 0.16, 0.25, 0.47)))


func remove_tower(c: Vector2i) -> void:
	if _tower_nodes.has(c):
		_tower_nodes[c].queue_free()
		_tower_nodes.erase(c)


func refresh_overcharge() -> void:
	for c in _tower_nodes:
		if world.towers.has(c):
			_tower_nodes[c].get_node("Overcharge").visible = world.towers[c].oc > 0.0
			_tower_nodes[c].get_node("Jam").visible = world.towers[c].get("jam", 0.0) > 0.0


func refresh_links() -> void:
	for l in _links:
		l.queue_free()
	_links.clear()
	for link in world.combo_links:
		var a: Vector3 = world.cell_to_world(link[0]) + Vector3(0, 0.3, 0)
		var b: Vector3 = world.cell_to_world(link[1]) + Vector3(0, 0.3, 0)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.035
		cyl.bottom_radius = 0.035
		cyl.height = a.distance_to(b)
		var n := mesh_node(cyl, mat(Color("#FFD34D"), 3.0, 0.9, true), (a + b) / 2.0)
		n.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
		add_child(n)
		_links.append(n)


func _pop_in(n: Node3D) -> void:
	n.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ================================================================ snuffers

func clear_snuffers() -> void:
	for id in _snuffers:
		_snuffers[id].node.queue_free()
	_snuffers.clear()


func _make_snuffer(type: String) -> Dictionary:
	var d: Dictionary = D.SNUFFERS[type]
	var root := Node3D.new()
	var body_root := Node3D.new()
	body_root.name = "Body"
	root.add_child(body_root)
	var path := "res://assets/snuffers/%s.glb" % ("shellback" if type == "big_shellback" else type)
	var m := model(path)
	if m == null:
		m = Shapes.snuffer(type)
	if m == null:
		m = Node3D.new()
		m.add_child(mesh_node(sphere(0.26), mat(SNUFFER_COLORS.get(type, Color("#7B5BD6"))), Vector3(0, 0.26, 0)))
		for side in [-1, 1]:
			m.add_child(mesh_node(sphere(0.06), mat(Color("#FFF3D6"), 0.5), Vector3(0.1 * side, 0.34, -0.22)))
		if d.air:
			for side in [-1, 1]:
				var wing := Node3D.new()
				wing.name = "Wing_L" if side < 0 else "Wing_R"
				var wm := BoxMesh.new()
				wm.size = Vector3(0.36, 0.02, 0.24)
				wing.add_child(mesh_node(wm, mat(Color("#F7B6D9")), Vector3(0.2 * side, 0, 0)))
				wing.position = Vector3(0.2 * side, 0.3, 0)
				m.add_child(wing)
	body_root.add_child(m)
	body_root.scale = Vector3.ONE * d.size
	var wings: Array = []
	for wn in ["Wing_L*", "Wing_R*"]:
		var wnode := m.find_child(wn, true, false)
		if wnode:
			wings.append(wnode)
	var bar_bg := mesh_node(_quad(0.62, 0.09), mat(Color("#2B1B2E"), 0.0, 0.85, true), Vector3(0, 0.8 * d.size + 0.35, 0))
	(bar_bg.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_bg.visible = false
	root.add_child(bar_bg)
	var bar_fg := mesh_node(_quad(0.58, 0.06), mat(Color("#7BE07B"), 0.5, 1.0, true).duplicate(), Vector3(0, 0.8 * d.size + 0.35, 0.01))
	(bar_fg.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_fg.visible = false
	root.add_child(bar_fg)
	var ring_n := mesh_node(ring(0.32 * d.size, 0.05), mat(Color("#A8E6FF"), 1.5, 0.8, true), Vector3(0, 0.04, 0))
	ring_n.visible = false
	root.add_child(ring_n)
	var ice_box := BoxMesh.new()
	ice_box.size = Vector3.ONE * 0.62 * d.size
	var ice := mesh_node(ice_box, mat(Color("#D9F6FF"), 0.6, 0.45), Vector3(0, 0.3 * d.size, 0))
	ice.visible = false
	root.add_child(ice)
	var bubble := mesh_node(sphere(0.42 * d.size), mat(Color("#BFEFFF"), 0.6, 0.35), Vector3(0, 0.3 * d.size, 0))
	bubble.visible = false
	root.add_child(bubble)
	var honey := mesh_node(ring(0.3 * d.size, 0.08), mat(Color("#F2A33D"), 0.4, 0.85), Vector3(0, 0.05, 0))
	honey.visible = false
	root.add_child(honey)
	add_child(root)
	return {node = root, body = body_root, target = Vector3.ZERO, type = type, bg = bar_bg, fg = bar_fg,
		ring = ring_n, ice = ice, wings = wings, air = d.air, phase = randf() * TAU,
		bubble = bubble, honey = honey, hidden = false}


func _quad(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	return q


func apply_snapshot(ids: PackedInt32Array, pos: PackedVector2Array, types: PackedByteArray, hp: PackedByteArray,
		status: PackedByteArray, shots: Array, pops: PackedVector2Array) -> void:
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		seen[id] = true
		var type: String = D.SNUFFER_TYPES[types[i]]
		if not _snuffers.has(id):
			_snuffers[id] = _make_snuffer(type)
			_snuffers[id].node.position = Vector3(pos[i].x, 0, pos[i].y)
			_snuffers[id].last_hp = 255
			if D.SNUFFERS[type].get("boss", false):
				shake(0.35)
		var s: Dictionary = _snuffers[id]
		s.target = Vector3(pos[i].x, 0, pos[i].y)
		if hp[i] < int(s.last_hp):
			_hit_squash(s.body)
		s.last_hp = hp[i]
		var r := hp[i] / 255.0
		s.bg.visible = r < 0.999
		s.fg.visible = r < 0.999
		s.fg.scale.x = maxf(r, 0.02)
		(s.fg.material_override as StandardMaterial3D).albedo_color = Color("#7BE07B") if r > 0.5 else (Color("#FFD34D") if r > 0.25 else Color("#FF7A7A"))
		s.ring.visible = (status[i] & 1) != 0
		s.ice.visible = (status[i] & 2) != 0
		s.bubble.visible = (status[i] & 4) != 0
		s.honey.visible = (status[i] & 16) != 0
		var hidden := (status[i] & 8) != 0
		if hidden != s.hidden:
			s.hidden = hidden
			_set_ghost(s.body, 0.75 if hidden else 0.0)
			s.bg.visible = s.bg.visible and not hidden
			s.fg.visible = s.fg.visible and not hidden
	for id in _snuffers.keys():
		if not seen.has(id):
			_snuffers[id].node.queue_free()
			_snuffers.erase(id)
	for shot in shots:
		_play_shot(shot[0], shot[1], shot[2])
		var snd: String = ["shot_pebble", "shot_jelly", "shot_frost", "shot_seed", "beam", "drum", "swarm", "honey",
			"bounce", "shield_pop", "split", "shield_up", "jam"][clampi(int(shot[2]), 0, 12)]
		Sfx.play(snd)
		if int(shot[2]) == 1:
			Sfx.play_later("splat", 0.42)
	for p in pops:
		_confetti(Vector3(p.x, 0.4, p.y))
		_coin_pop(Vector3(p.x, 0.5, p.y))
		Sfx.play("snuffer_pop")
	if pops.size() > 0:
		Sfx.play("coin", -8.0)


# ================================================================ heroes

func apply_heroes(names: PackedStringArray, positions: PackedVector2Array, kinds: PackedByteArray) -> void:
	var seen := {}
	for i in names.size():
		var n := names[i]
		seen[n] = true
		var hero: String = D.HERO_ORDER[kinds[i]]
		if not _heroes.has(n) or _heroes[n].hero != hero:
			if _heroes.has(n):
				_heroes[n].node.queue_free()
			_heroes[n] = _make_hero(n, hero)
			_heroes[n].node.position = Vector3(positions[i].x, 0, positions[i].y)
		_heroes[n].target = Vector3(positions[i].x, 0, positions[i].y)
	for n in _heroes.keys():
		if not seen.has(n) and n != Net.my_name:
			_heroes[n].node.queue_free()
			_heroes.erase(n)


func _make_hero(player_name: String, hero: String) -> Dictionary:
	var root := Node3D.new()
	var m := model("res://assets/heroes/%s.glb" % hero)
	if m == null:
		m = Node3D.new()
		var body := CapsuleMesh.new()
		body.radius = 0.22
		body.height = 0.7
		m.add_child(mesh_node(body, mat(HERO_COLORS[hero]), Vector3(0, 0.35, 0)))
		m.add_child(mesh_node(sphere(0.2), mat(Color("#FFE0C2")), Vector3(0, 0.85, 0)))
	m.name = "Model"
	m.scale = Vector3.ONE * 1.35
	root.add_child(m)
	var label := Label3D.new()
	label.text = "%s · %s" % [player_name, D.HEROES[hero].name]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.font_size = 40
	label.outline_size = 12
	label.position.y = 1.85
	label.font_size = 52
	label.modulate = HERO_COLORS[hero].lightened(0.3)
	root.add_child(label)
	if hero == "glint":
		root.add_child(mesh_node(ring(D.GLINT_AURA_RANGE, 0.03), mat(Color("#FFD34D"), 1.0, 0.35, true), Vector3(0, 0.05, 0)))
	add_child(root)
	return {node = root, target = root.position, hero = hero}


# ================================================================ effects

func _play_shot(c: Vector2i, to: Vector2, kind: int) -> void:
	var from: Vector3 = world.cell_to_world(c) + Vector3(0, 1.0, 0)
	var dest := Vector3(to.x, 0.35, to.y)
	if c == Vector2i(-1, -1):
		from = dest
	elif kind <= 8:
		_recoil(c)
	match kind:
		0:
			var p := mesh_node(sphere(0.07), mat(Color("#FFC44D"), 3.0), from)
			add_child(p)
			var tw := create_tween()
			tw.tween_property(p, "position", dest, 0.15)
			tw.tween_callback(p.queue_free)
		1:
			var blob := mesh_node(sphere(0.13), mat(Color("#7BE07B"), 1.5), from)
			add_child(blob)
			var tw := create_tween()
			tw.tween_method(func(t: float): blob.position = from.lerp(dest, t) + Vector3(0, sin(t * PI) * 1.4, 0), 0.0, 1.0, 0.35)
			tw.tween_callback(_jelly_land.bind(blob, dest))
		2:
			_ripple(world.cell_to_world(c) + Vector3(0, 0.15, 0), world.tower_range(c) if world.towers.has(c) else 2.2, Color("#A8E6FF"))


		3:
			var seed := mesh_node(sphere(0.08), mat(Color("#FFE680"), 4.0), from)
			add_child(seed)
			var trail := mesh_node(CylinderMesh.new(), mat(Color("#FFE680"), 3.0, 0.5, true), from)
			(trail.mesh as CylinderMesh).top_radius = 0.025
			(trail.mesh as CylinderMesh).bottom_radius = 0.025
			(trail.mesh as CylinderMesh).height = 1.0
			add_child(trail)
			var tw := create_tween()
			tw.tween_method(_seed_step.bind(seed, trail, from, dest), 0.0, 1.0, 0.28)
			tw.tween_callback(seed.queue_free)
			tw.tween_callback(trail.queue_free)
		4:
			var a2 := from + Vector3(0, 0.1, 0)
			var beam := mesh_node(CylinderMesh.new(), mat(Color("#FFF0A0"), 5.0, 0.8, true), (a2 + dest) / 2.0)
			(beam.mesh as CylinderMesh).top_radius = 0.05
			(beam.mesh as CylinderMesh).bottom_radius = 0.05
			(beam.mesh as CylinderMesh).height = maxf(a2.distance_to(dest), 0.01)
			beam.quaternion = Quaternion(Vector3.UP, (dest - a2).normalized())
			add_child(beam)
			var tw2 := create_tween()
			tw2.tween_property(beam, "scale", Vector3(0.2, 1, 0.2), 0.16)
			tw2.tween_callback(beam.queue_free)
		5:
			var r2: float = world.tower_range(c) if world.towers.has(c) else 2.0
			_ripple(world.cell_to_world(c) + Vector3(0, 0.15, 0), r2, Color("#FF8A3D"))
			_ripple(world.cell_to_world(c) + Vector3(0, 0.15, 0), r2 * 0.6, Color("#FFD34D"))
		6:
			var bug := mesh_node(sphere(0.05), mat(Color("#E8FF6A"), 5.0), from)
			add_child(bug)
			var side := Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 0.6), randf_range(-0.6, 0.6))
			var tw3 := create_tween()
			tw3.tween_method(func(t: float): bug.position = from.lerp(dest, t) + side * sin(t * PI), 0.0, 1.0, 0.3)
			tw3.tween_callback(bug.queue_free)
		7:
			var glob := mesh_node(sphere(0.12), mat(Color("#F2A33D"), 1.0), from)
			add_child(glob)
			var tw4 := create_tween()
			tw4.tween_method(func(t: float): glob.position = from.lerp(dest, t) + Vector3(0, sin(t * PI) * 1.2, 0), 0.0, 1.0, 0.35)
			tw4.tween_callback(_honey_land.bind(glob, dest))
		8:
			_ripple(world.cell_to_world(c) + Vector3(0, 0.2, 0), 1.4, Color("#FF6FA5"))
			if _tower_nodes.has(c):
				var spring := _tower_nodes[c].find_child("Spring", true, false) as Node3D
				if spring:
					var tw5 := create_tween()
					tw5.tween_property(spring, "scale", Vector3(1, 1.5, 1), 0.08)
					tw5.tween_property(spring, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK)
		9:
			_ripple(dest, 0.6, Color("#BFEFFF"))
		10:
			_ripple(dest, 0.9, Color("#6FD36F"))
			_confetti(dest)
		11:
			_ripple(dest, 1.6, Color("#5EC8FF"))
		12:
			if _tower_nodes.has(c):
				_ripple(world.cell_to_world(c) + Vector3(0, 0.3, 0), 0.7, Color("#FFB627"))


func _seed_step(t: float, seed: Node3D, trail: Node3D, from: Vector3, dest: Vector3) -> void:
	seed.position = from.lerp(dest, t)
	var a := from.lerp(dest, maxf(0.0, t - 0.25))
	trail.position = (a + seed.position) / 2.0
	var dv := seed.position - a
	if dv.length() > 0.01:
		trail.quaternion = Quaternion(Vector3.UP, dv.normalized())
	trail.scale = Vector3(1, maxf(dv.length(), 0.01), 1)


func _honey_land(glob: Node3D, dest: Vector3) -> void:
	glob.queue_free()
	_ripple(dest, 1.1, Color("#F2A33D"))


## Fades a Snuffer's body (Shades are see-through until revealed).
func _set_ghost(body: Node3D, amount: float) -> void:
	for n in body.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).transparency = amount


func _jelly_land(blob: Node3D, dest: Vector3) -> void:
	blob.queue_free()
	_ripple(dest, 1.1, Color("#7BE07B"))


func _ripple(at: Vector3, radius: float, color: Color) -> void:
	var r := mesh_node(ring(1.0, 0.08), mat(color, 2.0, 0.8, true), Vector3(at.x, 0.12, at.z))
	r.scale = Vector3(0.2, 1, 0.2)
	add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "scale", Vector3(radius, 1, radius), 0.3)
	tw.tween_callback(r.queue_free)


## Small camera shake (bosses, Pip getting hit).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## A spinning coin that pops out of a popped Snuffer.
func _coin_pop(at: Vector3) -> void:
	if _coin_mesh == null:
		_coin_mesh = CylinderMesh.new()
		_coin_mesh.top_radius = 0.11
		_coin_mesh.bottom_radius = 0.11
		_coin_mesh.height = 0.03
		_coin_mesh.radial_segments = 14
		_coin_mat = mat(Color("#FFC44D"), 1.2)
	var c := mesh_node(_coin_mesh, _coin_mat, at)
	c.rotation.x = PI / 2
	add_child(c)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(c, "position", at + Vector3(randf_range(-0.2, 0.2), 1.1, randf_range(-0.2, 0.2)), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation:y", TAU * 2.0, 0.55)
	tw.tween_property(c, "scale", Vector3.ONE * 0.2, 0.25).set_delay(0.4)
	tw.chain().tween_callback(c.queue_free)


## A quick squash so you can see who got hit.
func _hit_squash(body: Node3D) -> void:
	if body.has_meta("squashing"):
		return
	body.set_meta("squashing", true)
	var base := body.scale
	var tw := create_tween()
	tw.tween_property(body, "scale", Vector3(base.x * 1.18, base.y * 0.8, base.z * 1.18), 0.05)
	tw.tween_property(body, "scale", base, 0.12)
	tw.tween_callback(body.remove_meta.bind("squashing"))


## Towers kick back a little when they fire.
func _recoil(c: Vector2i) -> void:
	if not _tower_nodes.has(c):
		return
	var model := _tower_nodes[c].get_node_or_null("Model") as Node3D
	if model == null or model.has_meta("kicking"):
		return
	model.set_meta("kicking", true)
	var base := model.scale
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3(base.x * 1.07, base.y * 0.92, base.z * 1.07), 0.05)
	tw.tween_property(model, "scale", base, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(model.remove_meta.bind("kicking"))


## Big celebration around Pip.
func celebrate() -> void:
	for k in 8:
		var a := k * TAU / 8.0
		get_tree().create_timer(k * 0.12).timeout.connect(_confetti.bind(_pip.position + Vector3(cos(a) * 1.6, 0.6, sin(a) * 1.6)))


func _confetti(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 22
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.6
	p.gravity = Vector3(0, -7, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var q := BoxMesh.new()
	q.size = Vector3(0.07, 0.07, 0.015)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = cm
	p.mesh = q
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([Color("#FF7AB6"), Color("#FFD34D"), Color("#7FE3F0"), Color("#9FE07B"), Color("#B48CF2")])
	p.color_initial_ramp = grad
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


# ================================================================ per frame

func mouse_cell() -> Variant:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit == null:
		return null
	var c: Vector2i = world.world_to_cell(hit)
	if not world.in_bounds(c):
		return null
	return c


func update_frame(delta: float) -> void:
	_time += delta
	var k := clampf(delta * 12.0, 0.0, 1.0)
	for id in _snuffers:
		var s: Dictionary = _snuffers[id]
		var node: Node3D = s.node
		var prev := node.position
		var tgt: Vector3 = s.target
		node.position = Vector3(lerpf(prev.x, tgt.x, k), 0, lerpf(prev.z, tgt.z, k))
		var dir := tgt - prev
		if Vector2(dir.x, dir.z).length() > 0.002:
			node.rotation.y = lerp_angle(node.rotation.y, atan2(dir.x, dir.z) + PI, k)
		var body: Node3D = s.body
		if s.air:
			body.position.y = 1.0 + sin(_time * 3.0 + s.phase) * 0.12
			for w in s.wings:
				(w as Node3D).rotation.z = sin(_time * 22.0 + s.phase) * 0.7 * (1 if String(w.name).begins_with("Wing_L") else -1)
		else:
			body.position.y = absf(sin(_time * 9.0 + s.phase)) * 0.08
	for n in _heroes:
		var h: Dictionary = _heroes[n]
		var hn: Node3D = h.node
		var tgt2: Vector3 = Vector3(world.my_pos.x, 0, world.my_pos.y) if n == Net.my_name else h.target
		var prev2 := hn.position
		hn.position = tgt2 if n == Net.my_name else prev2.lerp(tgt2, k)
		var d2 := hn.position - prev2
		if Vector2(d2.x, d2.z).length() > 0.001:
			hn.get_node("Model").rotation.y = lerp_angle(hn.get_node("Model").rotation.y, atan2(d2.x, d2.z), clampf(delta * 10.0, 0, 1))
	if not _heroes.has(Net.my_name) and world.hero_choice.has(Net.my_name):
		_heroes[Net.my_name] = _make_hero(Net.my_name, world.hero_choice[Net.my_name])
	_reach_ring.position = Vector3(world.my_pos.x, 0.05, world.my_pos.y)
	if _last_glow >= 0.0 and world.glow < _last_glow - 0.01 and world.phase != "build":
		shake(0.25)
		_flash_amt = 1.0
		_flinch = 1.0
	_last_glow = world.glow
	if _flash_amt > 0.0:
		_flash_amt = maxf(0.0, _flash_amt - delta * 2.0)
		(_flash.material as ShaderMaterial).set_shader_parameter("amount", _flash_amt)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.2)
		camera.position = _cam_base + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * _shake
	elif camera.position != _cam_base and _cam_base != Vector3.ZERO:
		camera.position = _cam_base
	var g := clampf(world.glow / D.PIP_MAX, 0.05, 1.0)
	_flinch = maxf(0.0, _flinch - delta * 4.0)
	_pip.scale = Vector3.ONE * (0.8 + 0.2 * g) * (1.0 - 0.25 * _flinch)
	_pip.position.y = sin(_time * 1.6) * 0.05
	_pip_light.light_energy = lerpf(_pip_light.light_energy, 0.6 + 2.6 * g, delta * 4.0)
	_pip_light.omni_range = lerpf(_pip_light.omni_range, 3.0 + 4.5 * g, delta * 4.0)
	var gr: float = world.glow_radius()
	_glow_ring.scale = Vector3(gr, 1, gr)
	for c in _tower_nodes:
		var bugs := _tower_nodes[c].find_child("Bugs", true, false) as Node3D
		if bugs:
			bugs.rotation.y += delta * 1.5
			bugs.position.y = sin(_time * 3.0 + c.x) * 0.03
		var jm: Node3D = _tower_nodes[c].get_node("Jam")
		if jm.visible:
			jm.rotation.y += delta * 9.0
		var sp: Node3D = _tower_nodes[c].get_node("Overcharge")
		if sp.visible:
			sp.rotation.y += delta * 4.0
	_update_hover()
	_update_selection()


func _update_hover() -> void:
	var c = mouse_cell()
	if c == null or world.towers.has(c):
		_hover.visible = false
		return
	_hover.visible = true
	_hover.position = world.cell_to_world(c) + Vector3(0, 0.04, 0)
	var ok: bool = world.can_place(c, Net.my_name, world.selected_type, false).ok
	(_hover.material_override as StandardMaterial3D).albedo_color = Color(0.3, 1.0, 0.6, 0.4) if ok else Color(1.0, 0.35, 0.35, 0.35)


func _update_selection() -> void:
	var c = world.selected_cell
	if c == null or not world.towers.has(c):
		_range_ring.visible = false
		return
	var r: float = world.tower_range(c)
	_range_ring.visible = r > 0.0
	_range_ring.position = world.cell_to_world(c) + Vector3(0, 0.06, 0)
	_range_ring.scale = Vector3(r, 1, r)
