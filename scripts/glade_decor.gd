extends Node3D
## Gumdrop Glade's scenery: the grassy tile board, a layered cake edge with
## frosting drips and sprinkles, glossy syrup pools, a candy meadow with a
## chocolate river, candy canes, marshmallow mushrooms, cupcakes, flowers,
## cookie stepping stones and lantern posts. Purely visual; it never touches
## game state. Everything is built from shapes and small shaders so it costs
## no extra model files.

const D := preload("res://scripts/data.gd")

var view: Node3D
var world: Node
var _rng := RandomNumberGenerator.new()
var _hw: float   # half board width
var _hh: float   # half board height
var _blocked: Array[Rect2] = []   # meadow areas to keep clear (x/z)
var _time := 0.0
var _swayers: Array = []      # [node, phase, amount]
var _bouncers: Array = []     # [node, phase, base_scale]
var _lanterns: Array = []     # [material, light, phase]
var _gate_lights: Array = []  # [light, phase]
var _eyes: Array = []         # {node, next, shut}
var _butterflies: Array = []  # {node, wings, center, rx, rz, speed, phase}

# ---------------------------------------------------------------- shaders
const NOISE := """
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
"""

const BOARD_SHADER := """
shader_type spatial;
uniform vec2 cells = vec2(24.0, 14.0);
uniform vec3 col_a = vec3(0.55, 0.80, 0.48);
uniform vec3 col_b = vec3(0.48, 0.74, 0.43);
uniform vec3 speck_a = vec3(1.0, 0.97, 0.98);
uniform vec3 speck_b = vec3(1.0, 0.72, 0.86);
varying vec3 wp;
%s
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = UV * cells;
	vec2 cell = floor(c);
	vec2 f = fract(c);
	float chk = mod(cell.x + cell.y, 2.0);
	vec3 col = mix(col_a, col_b, chk);
	col *= 0.95 + 0.09 * hash(cell);
	float n = noise(wp.xz * 1.6) * 0.6 + noise(wp.xz * 4.5) * 0.4;
	col = mix(col, col * vec3(0.88, 1.04, 0.82), smoothstep(0.5, 0.8, n));
	col = mix(col, col * vec3(1.08, 1.06, 0.9), smoothstep(0.55, 0.85, noise(wp.xz * 0.7 + 9.0)));
	vec2 e = min(f, 1.0 - f);
	float edge = min(e.x, e.y);
	col = mix(col * 1.16, col, smoothstep(0.0, 0.07, edge));
	col = mix(col * 0.78, col, smoothstep(0.0, 0.022, edge));
	// tiny clover flowers
	vec2 g = wp.xz * 7.0; vec2 gi = floor(g);
	if (hash(gi) > 0.978) {
		float d = length(fract(g) - 0.5);
		vec3 fc = hash(gi + 3.1) > 0.5 ? speck_a : speck_b;
		col = mix(col, fc, 1.0 - smoothstep(0.1, 0.17, d));
	}
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.92;
}
"""

const MEADOW_SHADER := """
shader_type spatial;
uniform vec3 ground_a = vec3(0.36, 0.63, 0.37);
uniform vec3 ground_b = vec3(0.45, 0.72, 0.41);
uniform vec3 patch_col = vec3(0.62, 0.80, 0.46);
varying vec3 wp;
%s
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = noise(wp.xz * 0.35) * 0.6 + noise(wp.xz * 1.3) * 0.4;
	vec3 col = mix(ground_a, ground_b, n);
	col = mix(col, patch_col, smoothstep(0.62, 0.9, noise(wp.xz * 0.2 + 4.0)) * 0.6);
	vec2 g = wp.xz * 5.0; vec2 gi = floor(g);
	float h = hash(gi);
	if (h > 0.975) {
		float d = length(fract(g) - 0.5);
		vec3 fc = h > 0.992 ? vec3(1.0, 0.9, 0.4) : (h > 0.983 ? vec3(1.0, 0.7, 0.85) : vec3(1.0, 1.0, 1.0));
		col = mix(col, fc, 1.0 - smoothstep(0.08, 0.15, d));
	}
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.95;
}
"""

const SPONGE_SHADER := """
shader_type spatial;
varying vec3 wp;
%s
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float y = wp.y;
	vec3 sponge = vec3(0.97, 0.80, 0.53);
	vec3 col = sponge * (0.92 + 0.12 * noise(wp.xz * 9.0 + y * 7.0));
	col = mix(col, vec3(0.91, 0.32, 0.47), smoothstep(-0.36, -0.34, y) * (1.0 - smoothstep(-0.27, -0.25, y)));
	col = mix(col, vec3(1.0, 0.96, 0.88), smoothstep(-0.25, -0.23, y) * (1.0 - smoothstep(-0.2, -0.18, y)));
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.85;
}
"""

const SYRUP_SHADER := """
shader_type spatial;
uniform float seed = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float t = TIME + seed;
	float wob = 0.035 * sin(atan(p.y, p.x) * 5.0 + t * 0.7 + seed);
	float d = pow(pow(abs(p.x), 4.0) + pow(abs(p.y), 4.0), 0.25) + wob;
	if (d > 0.96) { discard; }
	float rim = smoothstep(0.82, 0.96, d);
	float ripple = sin(length(p - vec2(0.15, -0.1)) * 13.0 - t * 2.2) * 0.5 + 0.5;
	vec3 col = mix(vec3(1.0, 0.70, 0.22), vec3(0.85, 0.42, 0.06), clamp(length(p) * 0.75, 0.0, 1.0));
	col = mix(col, vec3(0.52, 0.24, 0.05), rim);
	col += ripple * 0.06 * (1.0 - rim);
	float shine = 1.0 - smoothstep(0.0, 0.14, length(p - vec2(-0.4, -0.45)));
	col = mix(col, vec3(1.0, 0.96, 0.8), shine * 0.55);
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	EMISSION = pow(col, vec3(2.2)) * 0.12;
}
"""

const RIVER_SHADER := """
shader_type spatial;
%s
void fragment() {
	vec2 uv = UV * vec2(30.0, 1.0);
	float t = TIME * 0.35;
	float swirl = noise(vec2(uv.x * 1.2 - t * 3.0, uv.y * 3.0)) * 0.6 + noise(vec2(uv.x * 3.0 - t * 4.0, uv.y * 6.0)) * 0.4;
	vec3 col = mix(vec3(0.36, 0.20, 0.12), vec3(0.52, 0.31, 0.19), swirl);
	float cream = smoothstep(0.72, 0.8, noise(vec2(uv.x * 2.0 - t * 3.5, uv.y * 4.0 + 7.0)));
	col = mix(col, vec3(0.86, 0.70, 0.55), cream * 0.6);
	float bank = smoothstep(0.38, 0.5, abs(UV.y - 0.5));
	col = mix(col, vec3(0.25, 0.13, 0.07), bank);
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.18;
	SPECULAR = 0.7;
}
"""

const COOKIE_SHADER := """
shader_type spatial;
varying vec3 wp;
%s
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = noise(wp.xz * 6.0);
	vec3 col = mix(vec3(0.80, 0.55, 0.30), vec3(0.90, 0.66, 0.38), n);
	vec2 g = wp.xz * 5.0; vec2 gi = floor(g);
	if (hash(gi) > 0.72) {
		float d = length(fract(g) - 0.5);
		col = mix(col, vec3(0.28, 0.15, 0.09), 1.0 - smoothstep(0.14, 0.2, d));
	}
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.8;
}
"""

const WIND_SHADER := """
shader_type spatial;
uniform float amp = 0.08;
uniform float rough = 0.8;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(wp.y + 0.6, 0.0, 2.5);
	float t = TIME;
	vec3 off = vec3(sin(t * 1.7 + wp.x * 0.7 + wp.z * 0.5), 0.0, cos(t * 1.3 + wp.x * 0.4 - wp.z * 0.6) * 0.6) * amp * h * h;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = rough;
}
"""

const HOLLOW_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
%s
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float n = noise(UV * 5.0 + vec2(TIME * 0.12, TIME * 0.07));
	float n2 = noise(UV * 11.0 - vec2(TIME * 0.2, 0.0));
	float d = length(p * vec2(1.0, 0.85)) + (n - 0.5) * 0.35;
	float a = 1.0 - smoothstep(0.35, 0.95, d);
	vec3 col = mix(vec3(0.16, 0.08, 0.27), vec3(0.40, 0.20, 0.58), n * 0.7 + n2 * 0.3);
	ALBEDO = pow(col, vec3(2.2));
	ALPHA = a * 0.94;
	ROUGHNESS = 0.9;
}
"""

const SWIRL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(0.56, 0.31, 0.84, 1.0);
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 0.98) { discard; }
	float a = atan(p.y, p.x) / 6.2832;
	float band = step(0.5, fract(a + r * 2.6));
	vec3 dark = vec3(0.07, 0.04, 0.10);
	vec3 col = mix(dark, tint.rgb, band);
	col = mix(col, dark, smoothstep(0.88, 0.94, r));
	float shine = 1.0 - smoothstep(0.0, 0.2, length(p - vec2(-0.35, -0.35)));
	ALBEDO = col + shine * 0.25;
	ROUGHNESS = 0.2;
	SPECULAR = 0.8;
}
"""

const SPRINKLE_COLORS := [Color("#FF6FA5"), Color("#FFD34D"), Color("#6FD3FF"), Color("#9CF06F"), Color("#B48CF2"), Color("#FFFFFF")]
const CANDY := [Color("#F27BAA"), Color("#FFD34D"), Color("#7FC8F0"), Color("#B48CF2"), Color("#FF9466")]


func build(v: Node3D) -> void:
	view = v
	world = v.world
	_rng.seed = 2024
	_hw = world.W / 2.0
	_hh = world.H / 2.0
	_blocked = [Rect2(-_hw - 1.0, -_hh - 1.0, world.W + 2.0, world.H + 2.0)]
	_board()
	_cake_edge()
	_syrup()
	_meadow()
	_river()
	_stepping_stones()
	_snuffer_hollow()
	_lantern_posts()
	_candy_canes()
	_mushrooms()
	_cupcakes()
	_trees_and_gumdrops()
	_cotton_candy()
	_flowers_and_grass()
	_fireflies()
	_butterfly_flock()


# ================================================================ helpers

func _shader(code: String, uses_noise := true) -> ShaderMaterial:
	var s := Shader.new()
	s.code = code % NOISE if uses_noise else code
	var m := ShaderMaterial.new()
	m.shader = s
	return m


func _mesh(mesh: Mesh, material: Material, pos: Vector3, parent: Node = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	(parent if parent else self).add_child(m)
	return m


func _std(c: Color, rough: float, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _multi(mesh: Mesh, xforms: Array, colors: Array, rough := 0.6, cast_shadow := true, wind := 0.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if wind > 0.0:
		var wm := _shader(WIND_SHADER, false)
		wm.set_shader_parameter("amp", wind)
		wm.set_shader_parameter("rough", rough)
		mi.material_override = wm
	else:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = rough
		mi.material_override = m
	if not cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _sphere(r: float, segs := 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = segs / 2
	return s


func _cyl(top: float, bottom: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	return c


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


## A random meadow spot inside `area` that isn't on the board, river or a path.
func _spot(area: Rect2, pad := 0.4) -> Vector2:
	for tries in 40:
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		var ok := true
		for b in _blocked:
			if b.grow(pad).has_point(p):
				ok = false
				break
		if ok:
			return p
	return Vector2(INF, INF)


func _meadow_areas() -> Array[Rect2]:
	return [
		Rect2(-_hw - 7.0, -_hh - 6.5, world.W + 14.0, 5.0),   # back
		Rect2(-_hw - 7.0, -_hh - 1.5, 6.0, world.H + 3.0),    # left
		Rect2(_hw + 1.0, -_hh - 1.5, 6.0, world.H + 3.0),     # right
		Rect2(-_hw - 7.0, _hh + 1.0, world.W + 14.0, 4.5),    # front
	]


func _random_area() -> Rect2:
	var areas := _meadow_areas()
	var weights := [0.36, 0.22, 0.22, 0.2]
	var r := _rng.randf()
	for i in areas.size():
		r -= weights[i]
		if r <= 0.0:
			return areas[i]
	return areas[0]


# ================================================================ the board

func _board() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(world.W, world.H)
	var m := _shader(BOARD_SHADER)
	m.set_shader_parameter("cells", Vector2(world.W, world.H))
	_mesh(plane, m, Vector3(0, 0.0, 0))


func _cake_edge() -> void:
	# sponge with jam and cream layers
	var sponge := BoxMesh.new()
	sponge.size = Vector3(world.W + 0.9, 0.6, world.H + 0.9)
	_mesh(sponge, _shader(SPONGE_SHADER), Vector3(0, -0.31, 0))
	# piped frosting dollops around the top edge
	var dollops: Array = []
	var dcols: Array = []
	var rim := [
		[Vector3(-_hw - 0.42, 0, _hh + 0.42), Vector3(_hw + 0.42, 0, _hh + 0.42)],
		[Vector3(-_hw - 0.42, 0, -_hh - 0.42), Vector3(_hw + 0.42, 0, -_hh - 0.42)],
		[Vector3(-_hw - 0.42, 0, -_hh - 0.42), Vector3(-_hw - 0.42, 0, _hh + 0.42)],
		[Vector3(_hw + 0.42, 0, -_hh - 0.42), Vector3(_hw + 0.42, 0, _hh + 0.42)],
	]
	for e in rim:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var count := int(a.distance_to(b) / 0.34)
		for i in count + 1:
			var p := a.lerp(b, float(i) / count)
			var s := _rng.randf_range(0.92, 1.08)
			dollops.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.8, s)), p + Vector3(0, -0.02, 0)))
			dcols.append(Color("#FF94C2"))
			dollops.append(Transform3D(Basis().scaled(Vector3(0.55, 0.6, 0.55)), p + Vector3(0, 0.14, 0)))
			dcols.append(Color("#FFB8D8"))
	_multi(_sphere(0.27, 14), dollops, dcols, 0.35)
	# drips down the sides
	var drips: Array = []
	var dcol: Array = []
	var edges := [
		[Vector3(-_hw - 0.45, 0, _hh + 0.45), Vector3(_hw + 0.45, 0, _hh + 0.45), Vector3(0, 0, 1)],
		[Vector3(-_hw - 0.45, 0, -_hh - 0.45), Vector3(_hw + 0.45, 0, -_hh - 0.45), Vector3(0, 0, -1)],
		[Vector3(-_hw - 0.45, 0, -_hh - 0.45), Vector3(-_hw - 0.45, 0, _hh + 0.45), Vector3(-1, 0, 0)],
		[Vector3(_hw + 0.45, 0, -_hh - 0.45), Vector3(_hw + 0.45, 0, _hh + 0.45), Vector3(1, 0, 0)],
	]
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var n: Vector3 = e[2]
		var count := int(a.distance_to(b) / 0.42)
		for i in count:
			var p := a.lerp(b, (i + _rng.randf_range(0.2, 0.8)) / count)
			var length := _rng.randf_range(0.12, 0.42)
			var basis := Basis().scaled(Vector3(1, length / 0.3, 1))
			drips.append(Transform3D(basis, p + n * 0.08 + Vector3(0, -0.12 - length * 0.5, 0)))
			dcol.append(Color("#FF94C2"))
	_multi(_capsule(0.1, 0.3), drips, dcol, 0.35)
	# sprinkles on the frosting
	var spr: Array = []
	var scol: Array = []
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var n: Vector3 = e[2]
		var count := int(a.distance_to(b) * 6.0)
		for i in count:
			var p := a.lerp(b, _rng.randf()) + n * _rng.randf_range(-0.2, 0.2)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, PI / 2 + _rng.randf_range(-0.3, 0.3))
			spr.append(Transform3D(basis, p + Vector3(0, 0.22, 0)))
			scol.append(SPRINKLE_COLORS[_rng.randi() % SPRINKLE_COLORS.size()])
	_multi(_capsule(0.022, 0.11), spr, scol, 0.4, false)


func _syrup() -> void:
	# merge touching syrup cells into pools
	var left := {}
	for c in D.MAP.syrup:
		left[c] = true
	var k := 0
	while not left.is_empty():
		var start: Vector2i = left.keys()[0]
		var group: Array[Vector2i] = []
		var stack: Array[Vector2i] = [start]
		left.erase(start)
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			group.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if left.has(c + d):
					left.erase(c + d)
					stack.append(c + d)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in group:
			var w: Vector3 = world.cell_to_world(c)
			lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
			hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
		var plane := PlaneMesh.new()
		plane.size = Vector2(hi.x - lo.x + 1.0, hi.y - lo.y + 1.0)
		var m := _shader(SYRUP_SHADER, false)
		m.set_shader_parameter("seed", k * 2.7)
		var center := (lo + hi) / 2.0
		_mesh(plane, m, Vector3(center.x, 0.025, center.y))
		# a few syrup bubbles
		for i in 3:
			var b := _mesh(_sphere(_rng.randf_range(0.04, 0.08), 10), _std(Color("#FFC062"), 0.05, 0.2),
				Vector3(center.x + _rng.randf_range(-0.5, 0.5), 0.03, center.y + _rng.randf_range(-0.5, 0.5)))
			b.scale.y = 0.6
		k += 1


# ================================================================ meadow

func _meadow() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 70)
	_mesh(plane, _shader(MEADOW_SHADER), Vector3(0, -0.61, 0))


func _river() -> void:
	var z := -_hh - 3.4
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 1.9)
	_mesh(plane, _shader(RIVER_SHADER), Vector3(0, -0.58, z))
	_blocked.append(Rect2(-45, z - 1.15, 90, 2.3))
	# crumbly cookie banks
	var crumbs: Array = []
	var ccol: Array = []
	for side in [-1.0, 1.0]:
		var x := -26.0
		while x < 26.0:
			var r := _rng.randf_range(0.6, 1.0)
			crumbs.append(Transform3D(Basis().scaled(Vector3(r * 1.3, r * 0.45, r)), Vector3(x, -0.6, z + side * 1.02)))
			ccol.append(Color("#D9A066").darkened(_rng.randf_range(0.0, 0.18)))
			x += _rng.randf_range(0.25, 0.45)
	_multi(_sphere(0.16, 10), crumbs, ccol, 0.85)
	# a wafer bridge
	var plank := BoxMesh.new()
	plank.size = Vector3(0.34, 0.1, 2.6)
	var wafer := _std(Color("#F2C27A"), 0.7)
	for i in 6:
		_mesh(plank, wafer, Vector3(-4.0 + i * 0.38, -0.5, z))
	var rail := _cyl(0.05, 0.05, 2.3, 8)
	for s in [-1.0, 1.0]:
		var r := _mesh(rail, _std(Color("#E85D7A"), 0.4), Vector3(-4.0 + 0.95 + s * 1.2, -0.25, z))
		r.rotation.x = PI / 2


func _stepping_stones() -> void:
	var cookie := _shader(COOKIE_SHADER)
	var disc := _cyl(0.32, 0.34, 0.12, 20)
	for e in D.MAP.entrances:
		var w: Vector3 = world.cell_to_world(e)
		_blocked.append(Rect2(-_hw - 7.0, w.z - 0.9, 6.5, 1.8))
		for i in 5:
			var x := -_hw - 1.2 - i * 1.0
			var s := _mesh(disc, cookie, Vector3(x, -0.55, w.z + _rng.randf_range(-0.18, 0.18)))
			s.scale = Vector3.ONE * _rng.randf_range(0.85, 1.1)


func _lantern_posts() -> void:
	var pole := _cyl(0.05, 0.07, 1.3, 10)
	var dark := _std(Color("#3B2A55"), 0.5)
	var glass := _std(Color("#FFD27A"), 0.3, 3.0)
	var cap := _cyl(0.0, 0.2, 0.18, 8)
	var brass := _std(Color("#E0A646"), 0.35)
	var spots := [
		Vector3(-_hw - 0.45, 0, -_hh - 0.45), Vector3(_hw + 0.45, 0, -_hh - 0.45),
		Vector3(-_hw - 0.45, 0, _hh + 0.45), Vector3(_hw + 0.45, 0, _hh + 0.45),
		Vector3(_hw + 0.45, 0, -1.6), Vector3(_hw + 0.45, 0, 2.6),
	]
	for p in spots:
		var root := Node3D.new()
		root.position = p
		add_child(root)
		_mesh(pole, dark, Vector3(0, 0.55, 0), root)
		_mesh(BoxMesh.new(), brass, Vector3(0, 1.22, 0), root).scale = Vector3(0.26, 0.04, 0.26)
		var g := glass.duplicate() as StandardMaterial3D
		_mesh(_sphere(0.15, 12), g, Vector3(0, 1.37, 0), root).scale = Vector3(1, 1.15, 1)
		_mesh(cap, brass, Vector3(0, 1.6, 0), root)
		var light := OmniLight3D.new()
		light.light_color = Color("#FFC870")
		light.omni_range = 2.6
		light.light_energy = 1.2
		light.position = Vector3(0, 1.37, 0)
		root.add_child(light)
		_lanterns.append([g, light, _rng.randf() * 10.0])


func _candy_canes() -> void:
	var xforms: Array = []
	var cols: Array = []
	var count := 16
	for n in count:
		var p := _spot(_random_area(), 0.6)
		if p.x == INF:
			continue
		var h := _rng.randf_range(0.9, 1.5)
		var yaw := _rng.randf() * TAU
		var turn := Basis(Vector3.UP, yaw)
		var step := 0.12
		var i := 0
		var y := 0.0
		while y < h:   # the stick
			xforms.append(Transform3D(turn, Vector3(p.x, -0.6 + y, p.y)))
			cols.append(Color("#E8344F") if i % 2 == 0 else Color("#FFFFFF"))
			y += step
			i += 1
		var r := 0.26
		for a in range(0, 9):   # the hook
			var ang := PI * a / 8.0
			var local := Vector3(r - cos(ang) * r, sin(ang) * r, 0)
			var tilt := Basis(Vector3(0, 0, 1), -ang)
			xforms.append(Transform3D(turn * tilt, Vector3(p.x, -0.6 + h, p.y) + turn * local))
			cols.append(Color("#E8344F") if i % 2 == 0 else Color("#FFFFFF"))
			i += 1
		_blocked.append(Rect2(p.x - 0.4, p.y - 0.4, 0.8, 0.8))
	_multi(_capsule(0.09, 0.2), xforms, cols, 0.25)


func _mushrooms() -> void:
	var stem := _cyl(0.1, 0.13, 0.4, 12)
	var cream := _std(Color("#FFF4E6"), 0.7)
	var dot := _sphere(0.05, 8)
	for n in 14:
		var p := _spot(_random_area(), 0.5)
		if p.x == INF:
			continue
		var s := _rng.randf_range(0.7, 1.3)
		var root := Node3D.new()
		root.position = Vector3(p.x, -0.6, p.y)
		root.scale = Vector3.ONE * s
		root.rotation.y = _rng.randf() * TAU
		add_child(root)
		_bouncers.append([root, _rng.randf() * TAU, s])
		_mesh(stem, cream, Vector3(0, 0.2, 0), root)
		var capc: Color = [Color("#FF6F91"), Color("#FF8F6B"), Color("#B48CF2"), Color("#6FC3F0")][_rng.randi() % 4]
		var cap := _mesh(_sphere(0.3, 16), _std(capc, 0.45), Vector3(0, 0.42, 0), root)
		cap.scale = Vector3(1, 0.55, 1)
		for d in 5:
			var a := d * TAU / 5.0 + _rng.randf() * 0.4
			_mesh(dot, cream, Vector3(cos(a) * 0.17, 0.55, sin(a) * 0.17), root).scale = Vector3(1, 0.5, 1)
		_mesh(dot, cream, Vector3(0, 0.585, 0), root).scale = Vector3(1, 0.5, 1)
		_blocked.append(Rect2(p.x - 0.35 * s, p.y - 0.35 * s, 0.7 * s, 0.7 * s))


func _cupcakes() -> void:
	var spots := [Vector2(_hw + 2.4, -_hh + 1.0), Vector2(_hw + 3.6, _hh - 1.6), Vector2(-_hw - 3.2, -_hh - 0.2), Vector2(4.5, _hh + 2.4)]
	var wrappers := [Color("#7FC8F0"), Color("#F27BAA"), Color("#9CF06F"), Color("#FFD34D")]
	var frostings := [Color("#FFF0F6"), Color("#FFE6A8"), Color("#F6D3FF"), Color("#FFFFFF")]
	for i in spots.size():
		var p: Vector2 = spots[i]
		var root := Node3D.new()
		root.position = Vector3(p.x, -0.6, p.y)
		root.scale = Vector3.ONE * 1.25
		add_child(root)
		_mesh(_cyl(0.42, 0.32, 0.45, 14), _std(wrappers[i], 0.55), Vector3(0, 0.225, 0), root)
		var f := _std(frostings[i], 0.4)
		_mesh(_sphere(0.46, 18), f, Vector3(0, 0.52, 0), root).scale = Vector3(1, 0.5, 1)
		_mesh(_sphere(0.32, 16), f, Vector3(0, 0.72, 0), root).scale = Vector3(1, 0.6, 1)
		_mesh(_sphere(0.18, 14), f, Vector3(0, 0.88, 0), root).scale = Vector3(1, 0.8, 1)
		_mesh(_sphere(0.1, 12), _std(Color("#E0203F"), 0.2), Vector3(0, 1.06, 0), root)
		var spr: Array = []
		var sc: Array = []
		for k in 22:
			var a := _rng.randf() * TAU
			var rr := _rng.randf_range(0.15, 0.4)
			var y := 0.62 - rr * 0.35
			spr.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, PI / 2), root.position + Vector3(cos(a) * rr, y, sin(a) * rr) * 1.25))
			sc.append(SPRINKLE_COLORS[_rng.randi() % SPRINKLE_COLORS.size()])
		_multi(_capsule(0.025, 0.1), spr, sc, 0.4, false)
		_blocked.append(Rect2(p.x - 0.7, p.y - 0.7, 1.4, 1.4))


func _trees_and_gumdrops() -> void:
	for n in 8:
		var p := _spot(_random_area(), 0.9)
		if p.x == INF:
			continue
		var tree: Node3D = view.model("res://assets/props/lollipop_tree.glb")
		if tree == null:
			break
		tree.position = Vector3(p.x, -0.65, p.y)
		tree.scale = Vector3.ONE * _rng.randf_range(1.0, 1.6)
		tree.rotation.y = _rng.randf() * TAU
		add_child(tree)
		_swayers.append([tree, _rng.randf() * TAU, 0.035])
		_blocked.append(Rect2(p.x - 0.6, p.y - 0.6, 1.2, 1.2))
	for n in 12:
		var p := _spot(_random_area(), 0.4)
		if p.x == INF:
			continue
		for k in _rng.randi_range(1, 3):
			var g: Node3D = view.model("res://assets/props/gumdrop.glb")
			if g == null:
				return
			g.position = Vector3(p.x + _rng.randf_range(-0.35, 0.35), -0.6, p.y + _rng.randf_range(-0.35, 0.35))
			g.scale = Vector3.ONE * _rng.randf_range(0.6, 1.0)
			g.rotation.y = _rng.randf() * TAU
			add_child(g)
		_blocked.append(Rect2(p.x - 0.5, p.y - 0.5, 1.0, 1.0))


func _flowers_and_grass() -> void:
	var petals: Array = []
	var pcol: Array = []
	var centers: Array = []
	var ccol: Array = []
	var stems: Array = []
	var scol: Array = []
	var colors := [Color("#FFFFFF"), Color("#FF9EC7"), Color("#FFD34D"), Color("#B9A2FF"), Color("#7FD3FF")]
	for n in 260:
		var p := _spot(_random_area(), 0.12)
		if p.x == INF:
			continue
		var h := _rng.randf_range(0.12, 0.26)
		var base := Vector3(p.x, -0.6, p.y)
		stems.append(Transform3D(Basis(), base + Vector3(0, h * 0.5, 0)).scaled_local(Vector3(1, h / 0.2, 1)))
		scol.append(Color("#3F8F3C"))
		var c: Color = colors[_rng.randi() % colors.size()]
		for k in 5:
			var a := k * TAU / 5.0
			petals.append(Transform3D(Basis().scaled(Vector3(1, 0.4, 1)), base + Vector3(cos(a) * 0.055, h, sin(a) * 0.055)))
			pcol.append(c)
		centers.append(Transform3D(Basis(), base + Vector3(0, h + 0.015, 0)))
		ccol.append(Color("#FFB627") if c != Color("#FFD34D") else Color("#FF7A3D"))
	_multi(_cyl(0.012, 0.012, 0.2, 5), stems, scol, 0.8, false, 0.5)
	_multi(_sphere(0.045, 8), petals, pcol, 0.6, false, 0.5)
	_multi(_sphere(0.03, 8), centers, ccol, 0.6, false, 0.5)
	# grass tufts
	var blades: Array = []
	var bcol: Array = []
	for n in 700:
		var p := _spot(_random_area(), 0.05)
		if p.x == INF:
			continue
		var g := Color("#4E9A46").lightened(_rng.randf_range(0.0, 0.25))
		for k in 3:
			var tilt := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(0.1, 0.45))
			var h := _rng.randf_range(0.6, 1.1)
			blades.append(Transform3D(tilt.scaled(Vector3(1, h, 1)), Vector3(p.x, -0.6, p.y) + tilt * Vector3(0, 0.1 * h, 0)))
			bcol.append(g)
	_multi(_cyl(0.0, 0.035, 0.2, 4), blades, bcol, 0.9, false, 0.9)


func _cotton_candy() -> void:
	var puffs: Array = []
	var cols: Array = []
	var stems: Array = []
	var scol: Array = []
	var shades := [Color("#FFB8DA"), Color("#BFE3FF"), Color("#E3C8FF"), Color("#FFE0B8")]
	for n in 14:
		var p := _spot(_random_area(), 0.8)
		if p.x == INF:
			continue
		var c: Color = shades[_rng.randi() % shades.size()]
		var h := _rng.randf_range(0.6, 1.1)
		stems.append(Transform3D(Basis().scaled(Vector3(1, h / 0.2, 1)), Vector3(p.x, -0.6 + h * 0.5, p.y)))
		scol.append(Color("#F7EBDD"))
		for k in _rng.randi_range(5, 8):
			var off := Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.15, 0.3), _rng.randf_range(-0.35, 0.35))
			var r := _rng.randf_range(0.7, 1.1)
			puffs.append(Transform3D(Basis().scaled(Vector3.ONE * r), Vector3(p.x, -0.6 + h + 0.25, p.y) + off))
			cols.append(c.lightened(_rng.randf_range(0.0, 0.15)))
		_blocked.append(Rect2(p.x - 0.7, p.y - 0.7, 1.4, 1.4))
	_multi(_cyl(0.05, 0.06, 0.2, 8), stems, scol, 0.6, true, 0.025)
	_multi(_sphere(0.3, 14), puffs, cols, 0.9, true, 0.025)


# ================================================================ Snuffer Hollow
## A creeping purple shadow where the Snuffers come from: licorice-swirl
## trees, glowing mushrooms, mist rolling out of the gates and eyes that
## blink in the dark bushes. Spooky, but friendly-spooky.
func _snuffer_hollow() -> void:
	var gates: Array[float] = []
	for e in D.MAP.entrances:
		gates.append((world.cell_to_world(e) as Vector3).z)
	var patch := PlaneMesh.new()
	patch.size = Vector2(17.0, world.H + 6.0)
	_mesh(patch, _shader(HOLLOW_SHADER), Vector3(-_hw - 2.6, -0.595, 0))
	for z in gates:
		# purple glow that pulses at each gate
		var light := OmniLight3D.new()
		light.light_color = Color("#B57BFF")
		light.omni_range = 3.2
		light.light_energy = 1.6
		light.position = Vector3(-_hw - 0.9, 0.7, z)
		add_child(light)
		_gate_lights.append([light, _rng.randf() * TAU])
		_mist(Vector3(-_hw - 1.0, 0.1, z))
	# keep the cheerful props out of the hollow
	for z in gates:
		pass
	_blocked.append(Rect2(-_hw - 9.0, -_hh - 1.5, 8.6, world.H + 3.0))
	# licorice swirl trees, glowing mushrooms and dark bushes with eyes
	var lane_pad := 1.0
	var spots: Array[Vector2] = []
	for i in 40:
		var p := Vector2(_rng.randf_range(-_hw - 7.5, -_hw - 1.2), _rng.randf_range(gates[0] - 2.4, gates[gates.size() - 1] + 2.4))
		var ok := true
		for z in gates:
			if absf(p.y - z) < lane_pad:
				ok = false
		for q in spots:
			if q.distance_to(p) < 1.3:
				ok = false
		if ok:
			spots.append(p)
	var k := 0
	for p in spots:
		match k % 3:
			0: _licorice_tree(p)
			1: _eye_bush(p)
			2: _glow_shrooms(p)
		k += 1


func _licorice_tree(p: Vector2) -> void:
	var root := Node3D.new()
	root.position = Vector3(p.x, -0.6, p.y)
	root.rotation.y = _rng.randf() * TAU
	add_child(root)
	var h := _rng.randf_range(1.2, 1.8)
	_mesh(_cyl(0.05, 0.08, h, 8), _std(Color("#2A1B3A"), 0.5), Vector3(0, h / 2.0, 0), root)
	# a flat licorice swirl on top
	var disc := QuadMesh.new()
	disc.size = Vector2(1.0, 1.0)
	var sw := _shader(SWIRL_SHADER, false)
	sw.set_shader_parameter("tint", [Color("#8E4FD6"), Color("#3FB8C9"), Color("#D64F9C")][_rng.randi() % 3])
	var d := _mesh(disc, sw, Vector3(0, h + 0.45, 0), root)
	d.rotation.y = -root.rotation.y + _rng.randf_range(-0.4, 0.4)
	d.rotation.x = -0.35
	_swayers.append([root, _rng.randf() * TAU, 0.05])


func _eye_bush(p: Vector2) -> void:
	var root := Node3D.new()
	root.position = Vector3(p.x, -0.6, p.y)
	add_child(root)
	var dark := _std(Color("#3A2350"), 0.9)
	for i in 5:
		var b := _mesh(_sphere(0.32, 12), dark, Vector3(_rng.randf_range(-0.3, 0.3), 0.25 + _rng.randf_range(0.0, 0.2), _rng.randf_range(-0.25, 0.25)), root)
		b.scale = Vector3.ONE * _rng.randf_range(0.8, 1.15)
	# a pair of glowing eyes peeking out toward the board
	var eyes := Node3D.new()
	eyes.position = Vector3(0.22, 0.5, 0.3)
	eyes.rotation.y = -PI / 4
	root.add_child(eyes)
	var glow := _std(Color("#E8FF6A"), 0.3, 4.0)
	for s in [-1.0, 1.0]:
		var e := _mesh(_sphere(0.085, 10), glow, Vector3(0.12, 0, s * 0.12), eyes)
		e.scale = Vector3(0.6, 1.25, 1.0)
	_eyes.append({node = eyes, next = _rng.randf_range(0.5, 4.0), shut = 0.0})


func _glow_shrooms(p: Vector2) -> void:
	for i in _rng.randi_range(2, 4):
		var root := Node3D.new()
		var s := _rng.randf_range(0.4, 0.8)
		root.position = Vector3(p.x + _rng.randf_range(-0.4, 0.4), -0.6, p.y + _rng.randf_range(-0.4, 0.4))
		root.scale = Vector3.ONE * s
		add_child(root)
		_mesh(_cyl(0.08, 0.1, 0.4, 8), _std(Color("#D9CBEA"), 0.7), Vector3(0, 0.2, 0), root)
		var c: Color = [Color("#B36BFF"), Color("#6BE3FF"), Color("#FF6BD5")][_rng.randi() % 3]
		var cap := _mesh(_sphere(0.26, 14), _std(c, 0.4, 1.6), Vector3(0, 0.42, 0), root)
		cap.scale = Vector3(1, 0.5, 1)
		_bouncers.append([root, _rng.randf() * TAU, s])


func _mist(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = 30
	p.lifetime = 3.5
	p.preprocess = 3.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.3, 0.1, 0.5)
	p.direction = Vector3(1, 0.2, 0)
	p.spread = 35.0
	p.gravity = Vector3(0, 0.03, 0)
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.4
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.7, 0.5, 1.0, 0.0))
	ramp.add_point(0.25, Color(0.62, 0.42, 0.98, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.5, 0.3, 0.9, 0.0))
	p.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	m.albedo_texture = tex
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)


# ================================================================ little life
func _fireflies() -> void:
	var areas := _meadow_areas()
	for a in areas:
		var p := CPUParticles3D.new()
		p.position = Vector3(a.get_center().x, 0.2, a.get_center().y)
		p.amount = int(a.get_area() / 6.0)
		p.lifetime = 5.0
		p.preprocess = 5.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(a.size.x / 2.0, 0.4, a.size.y / 2.0)
		p.direction = Vector3(0, 1, 0)
		p.spread = 180.0
		p.gravity = Vector3(0, 0.04, 0)
		p.initial_velocity_min = 0.05
		p.initial_velocity_max = 0.2
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 0.9, 0.5, 0.0))
		ramp.add_point(0.3, Color(1, 0.92, 0.55, 1.0))
		ramp.add_point(0.7, Color(1, 0.85, 0.4, 1.0))
		ramp.set_color(ramp.get_point_count() - 1, Color(1, 0.8, 0.3, 0.0))
		p.color_ramp = ramp
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = Color(1, 0.85, 0.4)
		m.emission_energy_multiplier = 2.0
		var dot := SphereMesh.new()
		dot.radius = 0.035
		dot.height = 0.07
		dot.radial_segments = 6
		dot.rings = 3
		dot.material = m
		p.mesh = dot
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)


func _butterfly_flock() -> void:
	var colors := [Color("#FF8FC8"), Color("#FFD34D"), Color("#7FD3FF"), Color("#C9A2FF"), Color("#FF9E6B")]
	var areas := _meadow_areas()
	for i in 7:
		var a: Rect2 = areas[[0, 0, 1, 2, 2, 3, 0][i]]
		var root := Node3D.new()
		add_child(root)
		var c: Color = colors[i % colors.size()]
		var wing_mat := _std(c, 0.5, 0.3)
		wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var wings: Array = []
		for s in [-1.0, 1.0]:
			var pivot := Node3D.new()
			root.add_child(pivot)
			var w := BoxMesh.new()
			w.size = Vector3(0.2, 0.01, 0.16)
			_mesh(w, wing_mat, Vector3(s * 0.11, 0, 0), pivot)
			pivot.set_meta("side", s)
			wings.append(pivot)
		_mesh(_capsule(0.02, 0.14), _std(Color("#3B2A55"), 0.5), Vector3.ZERO, root).rotation.x = PI / 2
		_butterflies.append({node = root, wings = wings, center = a.get_center(),
			rx = a.size.x * 0.4, rz = a.size.y * 0.35, speed = _rng.randf_range(0.12, 0.22), phase = _rng.randf() * TAU})


func _process(delta: float) -> void:
	_time += delta
	var t := _time
	for s in _swayers:
		var n: Node3D = s[0]
		n.rotation.z = sin(t * 1.1 + s[1]) * s[2]
		n.rotation.x = cos(t * 0.9 + s[1]) * s[2] * 0.6
	for b in _bouncers:
		var n: Node3D = b[0]
		var k := sin(t * 2.2 + b[1]) * 0.04
		n.scale = Vector3(b[2] * (1.0 - k * 0.5), b[2] * (1.0 + k), b[2] * (1.0 - k * 0.5))
	for l in _lanterns:
		var f := 0.85 + 0.15 * sin(t * 7.0 + l[2]) * sin(t * 2.3 + l[2] * 1.7)
		(l[0] as StandardMaterial3D).emission_energy_multiplier = 3.0 * f
		(l[1] as OmniLight3D).light_energy = 1.2 * f
	for g in _gate_lights:
		(g[0] as OmniLight3D).light_energy = 1.3 + 0.7 * sin(t * 1.6 + g[1])
	for e in _eyes:
		var n: Node3D = e.node
		if e.shut > 0.0:
			e.shut -= delta
			n.scale.y = 0.1
			if e.shut <= 0.0:
				n.scale.y = 1.0
				e.next = _rng.randf_range(1.5, 5.0)
		else:
			e.next -= delta
			if e.next <= 0.0:
				e.shut = 0.14
		n.rotation.y = sin(t * 0.7 + n.get_instance_id() % 7) * 0.4
	for bf in _butterflies:
		var n: Node3D = bf.node
		var a: float = t * bf.speed + bf.phase
		var c: Vector2 = bf.center
		var pos := Vector3(c.x + cos(a) * bf.rx, 0.35 + sin(t * 2.0 + bf.phase) * 0.15, c.y + sin(a * 2.0) * bf.rz)
		var ahead := Vector3(c.x + cos(a + 0.05) * bf.rx, pos.y, c.y + sin((a + 0.05) * 2.0) * bf.rz)
		n.position = pos
		if pos.distance_to(ahead) > 0.0001:
			n.look_at(ahead, Vector3.UP)
		var flap := sin(t * 18.0 + bf.phase) * 0.9
		for w in bf.wings:
			(w as Node3D).rotation.z = flap * float(w.get_meta("side"))
