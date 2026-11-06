extends Node3D
## Phase 0 test map: a grid board, Pip at one end, a Snuffer spawn at the other.
## The server owns the board: it validates tower placements, moves Snuffers
## along the shortest open path, and broadcasts the results to every player.

const W := 20
const H := 12
const SPAWN := Vector2i(0, 6)
const PIP := Vector2i(19, 6)
const SNUFFER_SPEED := 2.2
const SPAWN_GAP := 1.0
const WAVE_SIZE := 8
const WAVE_BREAK := 6.0
const LEAK_DAMAGE := 5.0
const SNAPSHOT_RATE := 0.1

var TOWERS := {
	"pebble_popper": {name = "Pebble Popper", key = KEY_1, color = Color("#3FB6C4")},
	"jelly_lobber": {name = "Jelly Lobber", key = KEY_2, color = Color("#8C5BD6")},
	"frost_puff": {name = "Frost Puff", key = KEY_3, color = Color("#9EDCF5")},
	"hedge_block": {name = "Hedge Block", key = KEY_4, color = Color("#4FA44F")},
}
const TOWER_ORDER := ["pebble_popper", "jelly_lobber", "frost_puff", "hedge_block"]

var astar := AStarGrid2D.new()
var towers: Dictionary = {}  # Vector2i -> {type, owner}
var glow := 100.0

# server-only state
var _snuffers: Dictionary = {}  # id -> {pos: Vector2, path: Array[Vector2i], idx: int}
var _next_id := 1
var _spawn_left := 0
var _spawn_timer := 2.0
var _wave := 0
var _snapshot_timer := 0.0

# client-only state
var visual := true
var selected_type := "hedge_block"
var _tower_nodes: Dictionary = {}
var _snuffer_nodes: Dictionary = {}
var _snuffer_targets: Dictionary = {}
var _path_dots: Array[Node3D] = []
var _camera: Camera3D
var _hover: MeshInstance3D
var _pip_node: Node3D
var _pip_light: OmniLight3D
var _hud: Node


func _ready() -> void:
	name = "World"
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	visual = not Net.is_dedicated
	if visual:
		_build_scene()
		_refresh_path_preview()
		if not multiplayer.is_server():
			request_state.rpc_id(1)


# ================================================================ shared helpers

static func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x - W / 2.0 + 0.5, 0.0, c.y - H / 2.0 + 0.5)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x + W / 2.0), floori(p.z + H / 2.0))


func _in_bounds(c: Vector2i) -> bool:
	return astar.region.has_point(c)


func _path_from(c: Vector2i) -> Array[Vector2i]:
	return astar.get_id_path(c, PIP)


## A tower may go on an empty, in-bounds cell that keeps a path open from the
## spawn and from every Snuffer to Pip. The path can be shaped, never sealed.
func can_place(c: Vector2i, check_snuffers := true) -> Dictionary:
	if not _in_bounds(c):
		return {ok = false, why = "That's off the board."}
	if c == SPAWN or c == PIP:
		return {ok = false, why = "Keep the Waygate and Pip clear."}
	if towers.has(c):
		return {ok = false, why = "There's already a tower there."}
	if check_snuffers:
		for s in _snuffers.values():
			if world_to_cell(Vector3(s.pos.x, 0, s.pos.y)) == c:
				return {ok = false, why = "A Snuffer is standing there."}
	astar.set_point_solid(c, true)
	var ok := not _path_from(SPAWN).is_empty()
	if ok and check_snuffers:
		for s in _snuffers.values():
			if _path_from(world_to_cell(Vector3(s.pos.x, 0, s.pos.y))).is_empty():
				ok = false
				break
	astar.set_point_solid(c, false)
	if not ok:
		return {ok = false, why = "That would block the path. Snuffers must always have a way through."}
	return {ok = true, why = ""}


# ================================================================ server

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_server_spawn(delta)
	_server_move(delta)
	_snapshot_timer -= delta
	if _snapshot_timer <= 0.0:
		_snapshot_timer = SNAPSHOT_RATE
		_send_snapshot()


func _server_spawn(delta: float) -> void:
	if Net.players.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	if _spawn_left <= 0:
		_wave += 1
		_spawn_left = WAVE_SIZE
		_broadcast_announce("Wave %d is coming!" % _wave)
	var id := _next_id
	_next_id += 1
	var start := cell_to_world(SPAWN)
	_snuffers[id] = {pos = Vector2(start.x, start.z), path = _path_from(SPAWN), idx = 1}
	_spawn_left -= 1
	_spawn_timer = SPAWN_GAP if _spawn_left > 0 else WAVE_BREAK


func _server_move(delta: float) -> void:
	var leaked: Array[int] = []
	for id in _snuffers:
		var s: Dictionary = _snuffers[id]
		var step := SNUFFER_SPEED * delta
		while step > 0.0 and s.idx < s.path.size():
			var t := cell_to_world(s.path[s.idx])
			var target := Vector2(t.x, t.z)
			var d: float = s.pos.distance_to(target)
			if d <= step:
				s.pos = target
				s.idx += 1
				step -= d
			else:
				s.pos += (target - s.pos) / d * step
				step = 0.0
		if s.idx >= s.path.size():
			leaked.append(id)
	for id in leaked:
		_snuffers.erase(id)
		glow -= LEAK_DAMAGE
	if glow <= 0.0:
		glow = 100.0
		_snuffers.clear()
		_spawn_left = 0
		_spawn_timer = WAVE_BREAK
		_wave = 0
		_broadcast_announce("Pip's light went out! Resetting the test round.")


func _repath_all() -> void:
	for s in _snuffers.values():
		var here := world_to_cell(Vector3(s.pos.x, 0, s.pos.y))
		s.path = _path_from(here)
		s.idx = 0


func _send_snapshot() -> void:
	var ids := PackedInt32Array()
	var pos := PackedVector2Array()
	for id in _snuffers:
		ids.append(id)
		pos.append(_snuffers[id].pos)
	_broadcast(&"snapshot", [ids, pos, glow])


## Send to logged-in players only (people on the login screen have no World yet).
## The host, if playing, gets a direct call instead of a network message.
func _broadcast(method: StringName, args: Array) -> void:
	var local_done := false
	for id in Net.players.keys():
		if Net.is_local(id):
			callv(method, args)
			local_done = true
		else:
			callv("rpc_id", [id, method] + args)
	if not local_done and method == &"announce":
		callv(method, args)


func _broadcast_announce(text: String) -> void:
	_broadcast(&"announce", [text])


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return 1 if id == 0 else id


func _tell(peer_id: int, text: String) -> void:
	if Net.is_local(peer_id):
		_show_message(text)
	else:
		notice.rpc_id(peer_id, text)


@rpc("any_peer", "reliable")
func request_state() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not Net.players.has(id):
		return
	var cells := []
	for c in towers:
		cells.append([c, towers[c].type, towers[c].owner])
	full_state.rpc_id(id, cells, glow)


@rpc("any_peer", "reliable")
func request_place(c: Vector2i, type: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not Net.players.has(id) or not TOWERS.has(type):
		return
	var check := can_place(c)
	if not check.ok:
		_tell(id, check.why)
		return
	var owner_name: String = Net.players[id]
	towers[c] = {type = type, owner = owner_name}
	astar.set_point_solid(c, true)
	_repath_all()
	Accounts.add_stat(owner_name, "towers_placed")
	print("[server] %s placed %s at %s" % [owner_name, type, c])
	_broadcast(&"tower_placed", [c, type, owner_name])


@rpc("any_peer", "reliable")
func request_remove(c: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not Net.players.has(id) or not towers.has(c):
		return
	if towers[c].owner != Net.players[id]:
		_tell(id, "You can only remove your own towers.")
		return
	towers.erase(c)
	astar.set_point_solid(c, false)
	_repath_all()
	_broadcast(&"tower_removed", [c])


# ================================================================ client (all peers)

@rpc("authority", "reliable")
func full_state(cells: Array, g: float) -> void:
	for entry in cells:
		_apply_tower(entry[0], entry[1], entry[2])
	glow = g
	_refresh_path_preview()


@rpc("authority", "reliable")
func tower_placed(c: Vector2i, type: String, owner_name: String) -> void:
	_apply_tower(c, type, owner_name)
	_refresh_path_preview()
	print("[%s] sees %s's %s at %s" % [Net.my_name, owner_name, type, c])


@rpc("authority", "reliable")
func tower_removed(c: Vector2i) -> void:
	if not multiplayer.is_server():
		towers.erase(c)
		astar.set_point_solid(c, false)
	if _tower_nodes.has(c):
		_tower_nodes[c].queue_free()
		_tower_nodes.erase(c)
	_refresh_path_preview()


@rpc("authority", "unreliable_ordered")
func snapshot(ids: PackedInt32Array, positions: PackedVector2Array, g: float) -> void:
	glow = g
	if not visual:
		return
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		seen[id] = true
		_snuffer_targets[id] = Vector3(positions[i].x, 0.3, positions[i].y)
		if not _snuffer_nodes.has(id):
			var n := _make_snuffer()
			n.position = _snuffer_targets[id]
			add_child(n)
			_snuffer_nodes[id] = n
	for id in _snuffer_nodes.keys():
		if not seen.has(id):
			_snuffer_nodes[id].queue_free()
			_snuffer_nodes.erase(id)
			_snuffer_targets.erase(id)


@rpc("authority", "reliable")
func announce(text: String) -> void:
	_show_message(text)


@rpc("authority", "reliable")
func notice(text: String) -> void:
	_show_message(text)


func _apply_tower(c: Vector2i, type: String, owner_name: String) -> void:
	towers[c] = {type = type, owner = owner_name}
	astar.set_point_solid(c, true)
	if visual and not _tower_nodes.has(c):
		var node := _make_tower(type, owner_name)
		node.position = cell_to_world(c)
		add_child(node)
		_tower_nodes[c] = node


func _show_message(text: String) -> void:
	if OS.get_cmdline_user_args().size() > 0 and Net.my_name != "":
		print("[%s] message: %s" % [Net.my_name, text])
	if _hud:
		_hud.show_message(text)
	else:
		print("[%s] %s" % [Net.my_name if Net.my_name != "" else "server", text])


# ================================================================ visuals & input

func _process(delta: float) -> void:
	if not visual:
		return
	for id in _snuffer_nodes:
		var n: Node3D = _snuffer_nodes[id]
		n.position = n.position.lerp(_snuffer_targets[id], clampf(delta * 12.0, 0.0, 1.0))
	var g := clampf(glow / 100.0, 0.05, 1.0)
	_pip_light.light_energy = lerpf(_pip_light.light_energy, 0.6 + 2.4 * g, delta * 4.0)
	_pip_light.omni_range = lerpf(_pip_light.omni_range, 2.5 + 4.0 * g, delta * 4.0)
	_pip_node.scale = Vector3.ONE * (0.75 + 0.25 * g)
	if _hud:
		_hud.set_glow(glow)
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if not visual:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		for t in TOWERS:
			if event.keycode == TOWERS[t].key:
				select_tower(t)
	if event is InputEventMouseButton and event.pressed:
		var c = _mouse_cell()
		if c == null:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			place_tower(c, selected_type)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			remove_tower(c)


func select_tower(t: String) -> void:
	selected_type = t
	if _hud:
		_hud.set_selected(t)


func place_tower(c: Vector2i, type: String) -> void:
	var check := can_place(c, false)
	if not check.ok:
		_show_message(check.why)
		return
	if multiplayer.is_server():
		request_place(c, type)
	else:
		request_place.rpc_id(1, c, type)


func remove_tower(c: Vector2i) -> void:
	if not towers.has(c):
		return
	if multiplayer.is_server():
		request_remove(c)
	else:
		request_remove.rpc_id(1, c)


func _mouse_cell() -> Variant:
	if _camera == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mp)
	var dir := _camera.project_ray_normal(mp)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit == null:
		return null
	var c: Vector2i = world_to_cell(hit)
	if not _in_bounds(c):
		return null
	return c


func _update_hover() -> void:
	var c = _mouse_cell()
	if c == null:
		_hover.visible = false
		return
	_hover.visible = true
	_hover.position = cell_to_world(c) + Vector3(0, 0.03, 0)
	var ok: bool = can_place(c, false).ok
	var m: StandardMaterial3D = _hover.material_override
	m.albedo_color = Color(0.3, 1.0, 0.6, 0.35) if ok else Color(1.0, 0.35, 0.35, 0.35)


func _refresh_path_preview() -> void:
	if not visual:
		return
	for d in _path_dots:
		d.queue_free()
	_path_dots.clear()
	var path := _path_from(SPAWN)
	for i in range(1, path.size() - 1):
		var dot := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.07
		m.height = 0.14
		dot.mesh = m
		dot.material_override = _flat_mat(Color("#F5B83D"), 0.8)
		dot.position = cell_to_world(path[i]) + Vector3(0, 0.08, 0)
		add_child(dot)
		_path_dots.append(dot)


func _flat_mat(c: Color, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _make_tower(type: String, owner_name: String) -> Node3D:
	var root := Node3D.new()
	var path := "res://assets/towers/%s.glb" % type
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if scene:
		var model := scene.instantiate()
		model.scale = Vector3.ONE * 0.9
		root.add_child(model)
	else:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.8, 0.8, 0.8)
		box.mesh = bm
		box.position.y = 0.4
		box.material_override = _flat_mat(TOWERS[type].color)
		root.add_child(box)
	var label := Label3D.new()
	label.text = owner_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.font_size = 48
	label.outline_size = 12
	label.position.y = 2.15
	root.add_child(label)
	return root


func _make_snuffer() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.26
	sm.height = 0.48
	body.mesh = sm
	body.material_override = _flat_mat(Color("#6E4BC2"))
	root.add_child(body)
	for side in [-1, 1]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.06
		em.height = 0.12
		eye.mesh = em
		eye.material_override = _flat_mat(Color("#FFF3D6"), 0.5)
		eye.position = Vector3(0.1 * side, 0.08, 0.22)
		root.add_child(eye)
	return root


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0B1226")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8FA3D6")
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	_camera = Camera3D.new()
	_camera.fov = 45
	add_child(_camera)
	_camera.position = Vector3(0, 15.5, 10.5)
	_camera.look_at(Vector3(0, 0, 0.6))

	# board tiles in a gentle checker so the grid reads clearly
	var tile_a := _flat_mat(Color("#2E3F66"))
	var tile_b := _flat_mat(Color("#33476F"))
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(0.96, 0.1, 0.96)
	for x in W:
		for y in H:
			var t := MeshInstance3D.new()
			t.mesh = tile_mesh
			t.material_override = tile_a if (x + y) % 2 == 0 else tile_b
			t.position = cell_to_world(Vector2i(x, y)) + Vector3(0, -0.05, 0)
			add_child(t)

	var gate := MeshInstance3D.new()
	var gm := TorusMesh.new()
	gm.inner_radius = 0.3
	gm.outer_radius = 0.45
	gate.mesh = gm
	gate.material_override = _flat_mat(Color("#8C5BD6"), 1.5)
	gate.position = cell_to_world(SPAWN) + Vector3(0, 0.05, 0)
	add_child(gate)

	_pip_node = Node3D.new()
	_pip_node.position = cell_to_world(PIP) + Vector3(0, 0.45, 0)
	var pip := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.38
	pm.height = 0.76
	pip.mesh = pm
	pip.material_override = _flat_mat(Color("#FFC44D"), 2.0)
	_pip_node.add_child(pip)
	add_child(_pip_node)
	_pip_light = OmniLight3D.new()
	_pip_light.light_color = Color("#FFC44D")
	_pip_light.position = _pip_node.position + Vector3(0, 0.4, 0)
	_pip_light.light_energy = 3.0
	_pip_light.omni_range = 6.5
	add_child(_pip_light)

	_hover = MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.96, 0.04, 0.96)
	_hover.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover.material_override = hmat
	add_child(_hover)

	_hud = preload("res://scripts/hud.gd").new()
	add_child(_hud)
	_hud.setup(self)
