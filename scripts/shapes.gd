extends RefCounted
## Built-in looks for towers and Snuffers that don't have a Blender model yet.
## board_view uses a .glb from assets/ when there is one, and these otherwise,
## so a modelled version can be dropped in later without code changes.
## Everything sits on the ground at y = 0 and fits in one tile (~0.9 wide).

static var _mats := {}

const BRASS := Color("#E0A646")
const BRASS_DARK := Color("#9C6A24")
const WOOD := Color("#9A6238")
const STONE := Color("#B9B2C9")
const GLOW := Color("#FFD27A")


static func m(c: Color, emit := 0.0, alpha := 1.0, metal := 0.0, rough := 0.55) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [c.to_html(), emit, alpha, metal, rough]
	if _mats.has(key):
		return _mats[key]
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(c, alpha)
	mt.metallic = metal
	mt.roughness = rough
	if emit > 0.0:
		mt.emission_enabled = true
		mt.emission = c
		mt.emission_energy_multiplier = emit
	if alpha < 1.0:
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = mt
	return mt


static func part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func cyl(top: float, bottom: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	return c


static func ball(r: float, segs := 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = segs / 2
	return s


static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func torus(r: float, thick: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - thick
	t.outer_radius = r
	t.rings = 24
	t.ring_segments = 10
	return t


## The shared brass-and-stone plinth every lantern tower stands on.
static func plinth(root: Node3D, color := STONE) -> void:
	part(root, cyl(0.42, 0.45, 0.12, 8), m(color, 0.0, 1.0, 0.0, 0.8), Vector3(0, 0.06, 0))
	part(root, cyl(0.36, 0.4, 0.06, 8), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 0.15, 0))


## A little hanging lantern (the game's motif) at a position.
static func lantern(root: Node3D, at: Vector3, s := 1.0) -> void:
	part(root, cyl(0.0, 0.07 * s, 0.06 * s, 8), m(BRASS, 0.0, 1.0, 0.7, 0.35), at + Vector3(0, 0.1 * s, 0))
	part(root, cyl(0.05 * s, 0.05 * s, 0.11 * s, 8), m(GLOW, 2.5), at)
	part(root, cyl(0.065 * s, 0.065 * s, 0.02 * s, 8), m(BRASS, 0.0, 1.0, 0.7, 0.35), at - Vector3(0, 0.065 * s, 0))


# ================================================================ towers

static func tower(type: String) -> Node3D:
	var r := Node3D.new()
	match type:
		"starseed_sling":
			plinth(r)
			part(r, cyl(0.05, 0.06, 0.45, 8), m(WOOD), Vector3(0, 0.4, 0))
			for s in [-1.0, 1.0]:
				part(r, cyl(0.035, 0.045, 0.42, 8), m(WOOD), Vector3(s * 0.12, 0.78, 0), Vector3(0, 0, -s * 0.45))
				part(r, ball(0.05, 8), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(s * 0.22, 0.97, 0))
			part(r, box(0.42, 0.03, 0.03), m(Color("#E85D7A")), Vector3(0, 0.95, 0.02))
			part(r, ball(0.09, 12), m(Color("#FFE680"), 2.5), Vector3(0, 0.95, 0.08))
			for k in 5:
				var a := k * TAU / 5.0
				part(r, cyl(0.0, 0.03, 0.08, 4), m(Color("#FFE680"), 2.5), Vector3(cos(a) * 0.1, 0.95 + sin(a) * 0.1, 0.08), Vector3(0, 0, a - PI / 2))
			lantern(r, Vector3(0.0, 0.48, 0.12), 0.8)
		"beam_lantern":
			plinth(r)
			part(r, cyl(0.06, 0.09, 0.75, 10), m(BRASS_DARK, 0.0, 1.0, 0.6, 0.4), Vector3(0, 0.55, 0))
			part(r, cyl(0.2, 0.2, 0.05, 12), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 0.95, 0))
			part(r, cyl(0.15, 0.15, 0.26, 12), m(GLOW, 3.0), Vector3(0, 1.1, 0))
			for k in 4:
				var a := k * TAU / 4.0 + PI / 4
				part(r, box(0.03, 0.3, 0.03), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(cos(a) * 0.16, 1.1, sin(a) * 0.16))
			part(r, cyl(0.0, 0.22, 0.16, 12), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 1.31, 0))
			part(r, cyl(0.12, 0.06, 0.2, 12), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 1.1, 0.22), Vector3(PI / 2, 0, 0))
			part(r, cyl(0.1, 0.1, 0.02, 12), m(Color("#FFF6D0"), 4.0), Vector3(0, 1.1, 0.33), Vector3(PI / 2, 0, 0))
		"thunder_drum":
			plinth(r)
			part(r, cyl(0.32, 0.32, 0.42, 20), m(Color("#D9434F")), Vector3(0, 0.39, 0))
			part(r, cyl(0.33, 0.33, 0.05, 20), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 0.2, 0))
			part(r, cyl(0.33, 0.33, 0.05, 20), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 0.6, 0))
			part(r, cyl(0.3, 0.3, 0.02, 20), m(Color("#FFF1D6")), Vector3(0, 0.63, 0))
			for k in 6:
				var a := k * TAU / 6.0
				part(r, box(0.02, 0.4, 0.02), m(Color("#FFE680")), Vector3(cos(a) * 0.325, 0.4, sin(a) * 0.325), Vector3(0, -a, 0.35))
			for s in [-1.0, 1.0]:
				part(r, cyl(0.02, 0.02, 0.5, 6), m(WOOD), Vector3(s * 0.12, 0.85, 0.05), Vector3(0.3, 0, s * 0.5))
				part(r, ball(0.05, 8), m(Color("#FFF1D6")), Vector3(s * 0.24, 1.07, 0.12))
			lantern(r, Vector3(0, 0.95, -0.18), 0.8)
		"firefly_swarm":
			plinth(r)
			part(r, cyl(0.25, 0.27, 0.6, 16), m(Color("#BFE8FF"), 0.2, 0.35, 0.0, 0.1), Vector3(0, 0.48, 0))
			part(r, cyl(0.27, 0.27, 0.06, 16), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 0.81, 0))
			part(r, cyl(0.12, 0.2, 0.08, 16), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 0.88, 0))
			part(r, torus(0.08, 0.02), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 0.98, 0), Vector3(PI / 2, 0, 0))
			var bugs := Node3D.new()
			bugs.name = "Bugs"
			r.add_child(bugs)
			for k in 7:
				var a := k * 2.4
				part(bugs, ball(0.035, 8), m(Color("#E8FF6A"), 4.0), Vector3(cos(a) * 0.14, 0.3 + (k % 4) * 0.12, sin(a) * 0.14))
		"honey_hive":
			plinth(r)
			var widths := [0.3, 0.32, 0.3, 0.25, 0.17]
			for k in widths.size():
				part(r, torus(widths[k], 0.09), m(Color("#F2B33D")), Vector3(0, 0.27 + k * 0.13, 0))
			part(r, ball(0.12, 12), m(Color("#F2B33D")), Vector3(0, 0.88, 0))
			part(r, cyl(0.07, 0.07, 0.04, 12), m(Color("#4A2A14")), Vector3(0, 0.38, 0.27), Vector3(PI / 2, 0, 0))
			part(r, ball(0.05, 8), m(Color("#FFB627"), 0.6, 0.9, 0.0, 0.1), Vector3(0.12, 0.6, 0.27), Vector3.ZERO, Vector3(1, 1.6, 1))
			for k in 3:
				var a := k * 2.1
				part(r, ball(0.04, 8), m(Color("#FFD34D")), Vector3(cos(a) * 0.42, 0.7 + k * 0.08, sin(a) * 0.42))
			lantern(r, Vector3(-0.28, 0.55, 0.18), 0.7)
		"beacon_post":
			plinth(r)
			for k in 4:
				var y := 0.25 + k * 0.2
				var rad := 0.2 - k * 0.025
				part(r, cyl(rad - 0.025, rad, 0.2, 14), m(Color("#FFFFFF") if k % 2 == 0 else Color("#E8344F")), Vector3(0, y, 0))
			part(r, cyl(0.15, 0.15, 0.04, 14), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 1.05, 0))
			part(r, cyl(0.1, 0.1, 0.18, 12), m(Color("#FFF6D0"), 4.0), Vector3(0, 1.16, 0))
			part(r, cyl(0.0, 0.16, 0.14, 12), m(Color("#E8344F")), Vector3(0, 1.32, 0))
			part(r, ball(0.03, 8), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 1.41, 0))
		"bounce_pad":
			part(r, box(0.86, 0.14, 0.86), m(Color("#8E5BEA")), Vector3(0, 0.07, 0))
			part(r, box(0.9, 0.04, 0.9), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 0.15, 0))
			var spring := Node3D.new()
			spring.name = "Spring"
			r.add_child(spring)
			for k in 4:
				part(spring, torus(0.2, 0.035), m(Color("#D7DCE8"), 0.0, 1.0, 0.8, 0.3), Vector3(0, 0.22 + k * 0.08, 0))
			part(spring, cyl(0.36, 0.38, 0.08, 20), m(Color("#FF6FA5")), Vector3(0, 0.55, 0))
			part(spring, cyl(0.25, 0.25, 0.01, 20), m(Color("#FFD1E4")), Vector3(0, 0.595, 0))
		"mirror_stone":
			part(r, box(0.84, 0.5, 0.84), m(Color("#A49CC0"), 0.0, 1.0, 0.0, 0.85), Vector3(0, 0.25, 0))
			part(r, box(0.7, 0.18, 0.7), m(Color("#BDB6D6"), 0.0, 1.0, 0.0, 0.85), Vector3(0, 0.59, 0))
			part(r, cyl(0.28, 0.28, 0.06, 24), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 0.95, 0), Vector3(PI / 2, 0, 0))
			part(r, cyl(0.24, 0.24, 0.07, 24), m(Color("#E8F6FF"), 0.6, 1.0, 1.0, 0.03), Vector3(0, 0.95, 0.005), Vector3(PI / 2, 0, 0))
			part(r, box(0.08, 0.2, 0.08), m(BRASS, 0.0, 1.0, 0.7, 0.35), Vector3(0, 0.72, 0))
			for s in [-1.0, 1.0]:
				part(r, ball(0.06, 8), m(Color("#9FE3FF"), 1.5), Vector3(s * 0.3, 0.72, 0.3))
		_:
			return null
	return r


# ================================================================ snuffers

static func eyes(root: Node3D, y: float, z: float, spread := 0.1, s := 1.0, color := Color("#FFF3D6")) -> void:
	for side in [-1.0, 1.0]:
		part(root, ball(0.06 * s, 10), m(color, 0.6), Vector3(spread * side, y, z))
		part(root, ball(0.03 * s, 8), m(Color("#1B1638")), Vector3(spread * side, y, z - 0.04 * s))


static func snuffer(type: String) -> Node3D:
	var r := Node3D.new()
	match type:
		"splitblob", "big_splitblob":
			part(r, ball(0.28, 18), m(Color("#6FD36F"), 0.2, 0.85, 0.0, 0.15), Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1, 0.85, 1))
			part(r, ball(0.1, 12), m(Color("#9CF09C"), 0.2, 0.85, 0.0, 0.15), Vector3(0.12, 0.5, 0.05))
			part(r, ball(0.08, 12), m(Color("#9CF09C"), 0.2, 0.85, 0.0, 0.15), Vector3(-0.1, 0.48, 0.1))
			eyes(r, 0.3, -0.22)
		"blobling":
			part(r, ball(0.26, 14), m(Color("#9CF09C"), 0.2, 0.9, 0.0, 0.15), Vector3(0, 0.24, 0), Vector3.ZERO, Vector3(1, 0.85, 1))
			eyes(r, 0.28, -0.2, 0.09)
		"shade":
			var body := part(r, ball(0.26, 16), m(Color("#4B2F7A"), 0.3, 0.75), Vector3(0, 0.34, 0))
			body.name = "Ghost"
			part(r, cyl(0.24, 0.0, 0.35, 12), m(Color("#4B2F7A"), 0.3, 0.6), Vector3(0, 0.12, 0.04))
			eyes(r, 0.38, -0.2, 0.1, 1.0, Color("#B9F0FF"))
		"mender":
			part(r, ball(0.27, 16), m(Color("#FFF0F6")), Vector3(0, 0.27, 0))
			part(r, box(0.18, 0.06, 0.04), m(Color("#FF5E8A"), 0.8), Vector3(0, 0.36, -0.26))
			part(r, box(0.06, 0.18, 0.04), m(Color("#FF5E8A"), 0.8), Vector3(0, 0.36, -0.26))
			part(r, torus(0.17, 0.025), m(Color("#FFE680"), 2.5), Vector3(0, 0.66, 0))
			eyes(r, 0.24, -0.23, 0.1, 0.8)
		"bubbleguard", "big_bubbleguard":
			part(r, ball(0.27, 16), m(Color("#5EC8FF")), Vector3(0, 0.27, 0))
			part(r, cyl(0.015, 0.015, 0.25, 6), m(Color("#2A64B8")), Vector3(0, 0.62, 0))
			part(r, ball(0.09, 12), m(Color("#D9F6FF"), 0.8, 0.6, 0.0, 0.05), Vector3(0, 0.78, 0))
			eyes(r, 0.3, -0.23)
		"jammer":
			part(r, ball(0.27, 16), m(Color("#FF9466")), Vector3(0, 0.27, 0))
			part(r, box(0.34, 0.08, 0.06), m(Color("#3B2A55")), Vector3(0, 0.34, -0.22))
			for side in [-1.0, 1.0]:
				part(r, cyl(0.06, 0.06, 0.04, 10), m(Color("#9FE3FF"), 1.2), Vector3(side * 0.09, 0.34, -0.26), Vector3(PI / 2, 0, 0))
				part(r, cyl(0.012, 0.012, 0.3, 6), m(Color("#3B2A55")), Vector3(side * 0.1, 0.62, 0.02), Vector3(0, 0, side * 0.3))
				part(r, ball(0.045, 8), m(Color("#FFE24D"), 3.0), Vector3(side * 0.15, 0.77, 0.02))
		"sugar_snuffer":
			part(r, ball(0.3, 20), m(Color("#FF8FC8")), Vector3(0, 0.3, 0))
			part(r, ball(0.16, 14), m(Color("#FFF0F6")), Vector3(0, 0.25, -0.2), Vector3.ZERO, Vector3(1, 0.7, 0.6))
			part(r, cyl(0.17, 0.15, 0.08, 10), m(BRASS, 0.5, 1.0, 0.8, 0.3), Vector3(0, 0.6, 0))
			for k in 5:
				var a := k * TAU / 5.0
				part(r, cyl(0.0, 0.035, 0.12, 6), m(BRASS, 0.5, 1.0, 0.8, 0.3), Vector3(cos(a) * 0.14, 0.7, sin(a) * 0.14))
				part(r, ball(0.02, 6), m([Color("#FF5E8A"), Color("#5EC8FF"), Color("#9CF06F")][k % 3], 1.5), Vector3(cos(a) * 0.15, 0.62, sin(a) * 0.15))
			part(r, cyl(0.012, 0.012, 0.45, 6), m(Color("#FFFFFF")), Vector3(0.3, 0.35, -0.05), Vector3(0, 0, 0.2))
			part(r, cyl(0.1, 0.1, 0.02, 16), m(Color("#FF5E8A"), 0.3), Vector3(0.35, 0.6, -0.05), Vector3(PI / 2, 0, 0))
			eyes(r, 0.38, -0.25, 0.11, 1.1, Color("#FFF3D6"))
		_:
			return null
	return r
