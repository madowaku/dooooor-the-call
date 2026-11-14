extends SceneTree
## Renders turnaround sheets of the protagonist for eyeballing the model.
## Run WITHOUT --headless:  godot --path . -s tools/shot_human.gd
## Writes build/shots/human_<pose>.png (front | three-quarter | side | back, 512x384 each)
## and build/shots/human_face.png (head close-ups: front, 3/4, side, from below, game line of sight),
## human_game.png / human_game_close.png (room camera ~2.4 m up, 4-6 m away) and
## human_top.png (overhead door camera, 8.4 m up).

const W := 512
const H := 384
const VIEWS := {"front": 0.0, "3q": 40.0, "side": 90.0, "back": 180.0}

var h: Human
var cam: Camera3D


func _initialize() -> void:
	_run()


func _run() -> void:
	root.size = Vector2i(W, H)
	DisplayServer.window_set_size(Vector2i(W, H))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.12, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.31, 0.30)
	env.environment = e
	root.add_child(env)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.30, 0.28, 0.26)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	var light := OmniLight3D.new()
	light.position = Vector3(1.6, 2.6, -2.2)
	light.omni_range = 9.0
	light.light_energy = 1.6
	light.shadow_enabled = true
	root.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 1.6, 2.0)
	fill.omni_range = 7.0
	fill.light_energy = 0.35
	root.add_child(fill)
	cam = Camera3D.new()
	cam.fov = 38.0
	root.add_child(cam)
	cam.make_current()
	h = Human.new()
	root.add_child(h)
	h.set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))

	var jobs := [["idle", 0.0], ["walk_a", 0.0], ["walk_b", PI * 0.5], ["walk_c", PI * 0.85], ["reach", 0.0],
		["hold", 0.0], ["push", 0.0], ["pull", 0.0], ["pocket", 0.0], ["phone", 0.0], ["thud", 0.0], ["pat", 0.0]]
	for jb: Array in jobs:
		var name: String = jb[0]
		var pose := "walk" if name.begins_with("walk") else name
		_settle(pose, jb[1])
		h.show_knob(pose == "pocket" or pose == "reach")
		h.show_handset(pose == "phone")
		var sheet := Image.create(W * 4, H, false, Image.FORMAT_RGB8)
		var i := 0
		for v: String in VIEWS:
			_place_cam(VIEWS[v], 3.3, 0.95, 0.88)
			var img := await _grab()
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(W * i, 0))
			i += 1
		sheet.save_png("res://build/shots/human_%s.png" % name)
		print("saved human_", name)
	# head close-ups: front, 3/4, side at eye level | from slightly below | along the game camera's line
	_settle("idle", 0.0)
	h.show_knob(false)
	h.show_handset(false)
	var fs := Image.create(W * 5, H, false, Image.FORMAT_RGB8)
	var k := 0
	for spec: Array in [[0.0, 0.75, 1.58, 1.58], [35.0, 0.75, 1.58, 1.58], [90.0, 0.75, 1.58, 1.58],
			[15.0, 0.75, 1.46, 1.6], [25.0, 1.0, 1.78, 1.58]]:  # last: same ~10 deg down line as the room camera
		_place_cam(spec[0], spec[1], spec[2], spec[3])
		var img2 := await _grab()
		fs.blit_rect(img2, Rect2i(0, 0, W, H), Vector2i(W * k, 0))
		k += 1
	fs.save_png("res://build/shots/human_face.png")
	# typical room camera: ~2.4 m up, 4-6 m away, looking down ~20 deg, wide lens like the game
	cam.fov = 60.0
	var gs := Image.create(W * 3, H, false, Image.FORMAT_RGB8)
	k = 0
	for spec2: Array in [[10.0, 4.0], [35.0, 5.0], [-20.0, 6.0]]:
		var a := deg_to_rad(spec2[0])
		var d: float = spec2[1]
		var p := Vector3(sin(a) * d, 2.4, -cos(a) * d)
		var target := Vector3(0, 2.4 - tan(deg_to_rad(20.0)) * d, 0)
		cam.look_at_from_position(p, target)
		var img3 := await _grab()
		gs.blit_rect(img3, Rect2i(0, 0, W, H), Vector2i(W * k, 0))
		k += 1
	gs.save_png("res://build/shots/human_game.png")
	# a crop of the game-angle view (same line of sight, narrow lens) to judge the face at that angle
	cam.fov = 9.0
	var gc := Image.create(W * 2, H, false, Image.FORMAT_RGB8)
	k = 0
	for spec3: Array in [[10.0, 4.0], [35.0, 5.0]]:
		var a2 := deg_to_rad(spec3[0])
		var d2: float = spec3[1]
		cam.look_at_from_position(Vector3(sin(a2) * d2, 2.4, -cos(a2) * d2), Vector3(0, 1.45, 0))
		var img4 := await _grab()
		gc.blit_rect(img4, Rect2i(0, 0, W, H), Vector2i(W * k, 0))
		k += 1
	gc.save_png("res://build/shots/human_game_close.png")
	# overhead door camera (8.4 m up, 2.3 m behind, fov 52) in the hold pose, plus a zoomed crop
	var ts := Image.create(W * 3, H, false, Image.FORMAT_RGB8)
	k = 0
	for spec4: Array in [["hold", 52.0], ["hold", 14.0], ["walk", 14.0]]:
		_settle(spec4[0], PI * 0.5)
		cam.fov = spec4[1]
		cam.look_at_from_position(Vector3(0, 8.4, 2.3), Vector3(0, 0, -0.25), Vector3(0, 0, -1))
		var img5 := await _grab()
		ts.blit_rect(img5, Rect2i(0, 0, W, H), Vector2i(W * k, 0))
		k += 1
	ts.save_png("res://build/shots/human_top.png")
	cam.fov = 38.0
	print("SHOTS DONE")
	quit()


func _settle(pose: String, phase: float) -> void:
	h.pose = pose
	h.walk_speed = 0.0
	h._last_pose = pose
	h._blend_left = 0.0
	h._phase = phase
	h._time = 1.0
	h._shift = 0.0
	h._shift_target = 0.0
	h._shift_timer = 100.0
	for i in 40:
		h._tick()
	h._phase = phase
	h._tick()


## yaw in degrees: 0 = camera in front of the face (-Z), 90 = from the character's right (+X)
func _place_cam(yaw_deg: float, dist: float, cam_y: float, look_y: float) -> void:
	var a := deg_to_rad(yaw_deg)
	cam.look_at_from_position(Vector3(sin(a) * dist, cam_y, -cos(a) * dist), Vector3(0, look_y, 0))


func _grab() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if img.get_size() != Vector2i(W, H):
		img.resize(W, H, Image.INTERPOLATE_NEAREST)
	return img
