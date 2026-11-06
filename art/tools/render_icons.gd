extends SceneTree
## Renders 256px icons of the towers, heroes and Pip into assets/ui/icons/.
## Needs a display (it renders), e.g.:
##   godot --path . --rendering-driver opengl3 -s res://art/tools/render_icons.gd
## (art/ is hidden from the game by .gdignore, so copy this file next to the
## project root first or run it with an absolute path.)

const ITEMS := {
	"pebble_popper": "res://assets/towers/pebble_popper.glb",
	"jelly_lobber": "res://assets/towers/jelly_lobber.glb",
	"frost_puff": "res://assets/towers/frost_puff.glb",
	"hedge_block": "res://assets/towers/hedge_block.glb",
	"bramble": "res://assets/heroes/bramble.glb",
	"glint": "res://assets/heroes/glint.glb",
	"pip": "res://assets/pip/pip.glb",
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/icons"))
	_run.call_deferred()


func _run() -> void:
	for id in ITEMS:
		await _render(id, ITEMS[id])
	quit()


func _render(id: String, path: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#B8B0FF")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color("#FFF1D6")
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.6
	rim.light_color = Color("#9FD3FF")
	vp.add_child(rim)
	var scene: PackedScene = load(path)
	var m: Node3D = scene.instantiate()
	vp.add_child(m)
	# frame the model's bounds
	var aabb := _bounds(m)
	var center := aabb.get_center()
	var size := aabb.size.length()
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	var dir := Vector3(0.55, 0.55, 1.0).normalized()
	cam.position = center + dir * size * 1.75
	cam.look_at(center, Vector3.UP)
	for i in 6:
		await process_frame
	var img := vp.get_texture().get_image()
	img.save_png("res://assets/ui/icons/%s.png" % id)
	print("icon ", id)
	vp.queue_free()


func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out
