extends "res://scripts/glade_decor.gd"
## Tanglewood's scenery: a mossy board ringed by fallen logs, thorny bramble
## patches, a dusky forest floor, tall trees hung with lanterns, ferns,
## mushrooms, stepping stones, fireflies and the Snuffer Hollow by the
## entrances. Shares helpers (and the animation loop) with Gumdrop Glade.

func build(v: Node3D) -> void:
	view = v
	world = v.world
	_rng.seed = 4077
	_hw = world.W / 2.0
	_hh = world.H / 2.0
	_blocked = [Rect2(-_hw - 1.0, -_hh - 1.0, world.W + 2.0, world.H + 2.0)]
	_forest_board()
	_log_edge()
	_thorn_patches()
	_forest_floor()
	_stones()
	_snuffer_hollow()
	_lantern_trees()
	_mushrooms()
	_ferns()
	_flowers_and_grass()
	_fireflies()
	_fireflies()
	_butterfly_flock()


func _forest_board() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(world.W, world.H)
	var m := _shader(BOARD_SHADER)
	m.set_shader_parameter("cells", Vector2(world.W, world.H))
	m.set_shader_parameter("col_a", Vector3(0.42, 0.64, 0.38))
	m.set_shader_parameter("col_b", Vector3(0.36, 0.58, 0.34))
	m.set_shader_parameter("speck_a", Vector3(0.95, 0.95, 0.75))
	m.set_shader_parameter("speck_b", Vector3(0.75, 0.6, 0.95))
	_mesh(plane, m, Vector3.ZERO)


func _forest_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 70)
	var m := _shader(MEADOW_SHADER)
	m.set_shader_parameter("ground_a", Vector3(0.24, 0.40, 0.25))
	m.set_shader_parameter("ground_b", Vector3(0.31, 0.47, 0.28))
	m.set_shader_parameter("patch_col", Vector3(0.45, 0.38, 0.25))
	_mesh(plane, m, Vector3(0, -0.61, 0))


## Soil sides and a ring of fallen, mossy logs around the board.
func _log_edge() -> void:
	var soil := BoxMesh.new()
	soil.size = Vector3(world.W + 0.9, 0.6, world.H + 0.9)
	_mesh(soil, _std(Color("#6B4A30"), 0.95), Vector3(0, -0.31, 0))
	var bark := _std(Color("#7A5233"), 0.9)
	var end_mat := _std(Color("#D9B98A"), 0.8)
	var sides := [
		[Vector3(0, -0.05, _hh + 0.42), world.W + 1.1, 0.0],
		[Vector3(0, -0.05, -_hh - 0.42), world.W + 1.1, 0.0],
		[Vector3(-_hw - 0.42, -0.05, 0), world.H + 0.2, PI / 2],
		[Vector3(_hw + 0.42, -0.05, 0), world.H + 0.2, PI / 2],
	]
	for sd in sides:
		var lg := _mesh(_cyl(0.24, 0.24, sd[1], 14), bark, sd[0])
		lg.rotation = Vector3(0, sd[2], PI / 2)
		for e in [-1.0, 1.0]:
			var cap := _mesh(_cyl(0.23, 0.23, 0.02, 14), end_mat, sd[0] + Basis(Vector3.UP, sd[2]) * Vector3(e * sd[1] / 2.0, 0, 0))
			cap.rotation = Vector3(0, sd[2], PI / 2)
	# moss and tiny mushrooms along the logs
	var moss: Array = []
	var mcol: Array = []
	var caps: Array = []
	var ccol: Array = []
	for sd in sides:
		var count := int(sd[1] * 2.2)
		for i in count:
			var along: float = _rng.randf_range(-0.5, 0.5) * float(sd[1])
			var p: Vector3 = sd[0] + Basis(Vector3.UP, sd[2]) * Vector3(along, 0.2, _rng.randf_range(-0.08, 0.08))
			var sz := _rng.randf_range(0.6, 1.2)
			moss.append(Transform3D(Basis().scaled(Vector3(sz * 1.4, sz * 0.5, sz)), p))
			mcol.append(Color("#5E9E4A").lightened(_rng.randf_range(0.0, 0.2)))
			if _rng.randf() < 0.12:
				caps.append(Transform3D(Basis().scaled(Vector3(1, 0.5, 1)), p + Vector3(0, 0.1, 0)))
				ccol.append([Color("#FF6F91"), Color("#FFD34D"), Color("#FF8F6B")][_rng.randi() % 3])
	_multi(_sphere(0.12, 10), moss, mcol, 0.95)
	_multi(_sphere(0.07, 10), caps, ccol, 0.5)


## Bramble clusters on the thorn tiles: they scratch Snuffers that walk through.
func _thorn_patches() -> void:
	var spikes: Array = []
	var scol: Array = []
	var leaves: Array = []
	var lcol: Array = []
	var ground := PlaneMesh.new()
	ground.size = Vector2(0.98, 0.98)
	var gmat := _std(Color("#4A2F45"), 0.95)
	for c in D.MAP.thorns:
		var w: Vector3 = world.cell_to_world(c)
		_mesh(ground, gmat, w + Vector3(0, 0.01, 0))
		for k in 14:
			var p := w + Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))
			var tilt := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(0.2, 0.9))
			var h := _rng.randf_range(0.7, 1.3)
			spikes.append(Transform3D(tilt.scaled(Vector3(1, h, 1)), p + tilt * Vector3(0, 0.12 * h, 0)))
			scol.append(Color("#3B2A2E").lerp(Color("#7A3B4F"), _rng.randf()))
		for k in 4:
			leaves.append(Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), w + Vector3(_rng.randf_range(-0.3, 0.3), 0.08, _rng.randf_range(-0.3, 0.3))))
			lcol.append(Color("#3E6B2E").lightened(_rng.randf_range(0.0, 0.15)))
	_multi(_cyl(0.0, 0.03, 0.25, 5), spikes, scol, 0.6, true, 0.15)
	_multi(_sphere(0.14, 10), leaves, lcol, 0.9)


func _stones() -> void:
	var stone := _cyl(0.3, 0.34, 0.1, 9)
	var smat := _std(Color("#9C98A8"), 0.85)
	for e in D.MAP.entrances:
		var w: Vector3 = world.cell_to_world(e)
		_blocked.append(Rect2(-_hw - 7.0, w.z - 0.8, 6.5, 1.6))
		for i in 5:
			var s := _mesh(stone, smat, Vector3(-_hw - 1.2 - i * 1.0, -0.56, w.z + _rng.randf_range(-0.18, 0.18)))
			s.scale = Vector3.ONE * _rng.randf_range(0.8, 1.1)
			s.rotation.y = _rng.randf() * TAU


## Tall trees around the board; some hold a glowing lantern on a branch.
func _lantern_trees() -> void:
	var trunk_mat := _std(Color("#5E3F28"), 0.9)
	var leaf_shades := [Color("#123A1C"), Color("#1C4A24"), Color("#24562B"), Color("#163F2C")]
	var lights := 0
	for n in 26:
		var p := _spot(_random_area(), 1.0)
		if p.x == INF:
			continue
		var front := p.y > _hh
		var h := _rng.randf_range(1.6, 2.4) if front else _rng.randf_range(2.4, 3.6)
		var root := Node3D.new()
		root.position = Vector3(p.x, -0.6, p.y)
		root.rotation.y = _rng.randf() * TAU
		add_child(root)
		_mesh(_cyl(0.13, 0.22, h, 10), trunk_mat, Vector3(0, h / 2.0, 0), root)
		for k in 3:
			var a := k * TAU / 3.0
			_mesh(_cyl(0.03, 0.09, 0.5, 6), trunk_mat, Vector3(cos(a) * 0.2, 0.08, sin(a) * 0.2), root).rotation = Vector3(0, -a, 1.2)
		var leaves: Array = []
		var lcol: Array = []
		for k in _rng.randi_range(4, 6):
			var off := Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.2, 0.6), _rng.randf_range(-0.6, 0.6))
			var r := _rng.randf_range(0.8, 1.25)
			leaves.append(Transform3D(Basis().scaled(Vector3.ONE * r), Vector3(0, h + 0.3, 0) + off))
			lcol.append(leaf_shades[_rng.randi() % leaf_shades.size()])
		var mm := _multi(_sphere(0.65, 14), leaves, lcol, 0.9, true, 0.012)
		remove_child(mm)
		root.add_child(mm)
		_swayers.append([root, _rng.randf() * TAU, 0.015])
		if _rng.randf() < 0.55:
			var side := Vector3(0.75, h * 0.62, 0)
			var branch := _mesh(_cyl(0.025, 0.05, 0.8, 6), trunk_mat, Vector3(0.38, h * 0.62 + 0.1, 0), root)
			branch.rotation.z = PI / 2 - 0.25
			var lantern := Node3D.new()
			lantern.position = side + Vector3(0, -0.25, 0)
			root.add_child(lantern)
			_mesh(_cyl(0.004, 0.004, 0.25, 4), _std(Color("#2A1B3A"), 0.5), Vector3(0, 0.15, 0), lantern)
			var glass := _std(Color("#FFD27A"), 0.3, 3.0)
			_mesh(_cyl(0.07, 0.07, 0.14, 8), glass, Vector3.ZERO, lantern)
			_mesh(_cyl(0.0, 0.1, 0.07, 8), _std(Color("#E0A646"), 0.35), Vector3(0, 0.1, 0), lantern)
			var light: OmniLight3D = null
			if lights < 8:
				light = OmniLight3D.new()
				light.light_color = Color("#FFC870")
				light.omni_range = 3.0
				light.light_energy = 1.4
				lantern.add_child(light)
				lights += 1
			_lanterns.append([glass, light if light else OmniLight3D.new(), _rng.randf() * 10.0])
		_blocked.append(Rect2(p.x - 0.9, p.y - 0.9, 1.8, 1.8))


func _ferns() -> void:
	var fronds: Array = []
	var fcol: Array = []
	for n in 90:
		var p := _spot(_random_area(), 0.3)
		if p.x == INF:
			continue
		var c := Color("#3F7A3A").lightened(_rng.randf_range(0.0, 0.25))
		for k in 7:
			var a := k * TAU / 7.0 + _rng.randf() * 0.3
			var tilt := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, _rng.randf_range(0.8, 1.15))
			fronds.append(Transform3D(tilt.scaled(Vector3(0.6, 1.0, 0.25)), Vector3(p.x, -0.6, p.y) + tilt * Vector3(0, 0.2, 0)))
			fcol.append(c)
		_blocked.append(Rect2(p.x - 0.3, p.y - 0.3, 0.6, 0.6))
	_multi(_cyl(0.0, 0.08, 0.42, 4), fronds, fcol, 0.8, false, 0.35)
