extends SceneTree
## Headless smoke test for scripts/human.gd.
## Run: godot --headless --path . -s tools/test_human.gd

var _steps: int = 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var pre := Human.new()  # must be usable before entering the tree
	pre.show_knob(true)
	print("pre-tree hand: ", pre.right_hand_global())
	pre.free()

	var h := Human.new()
	root.add_child(h)
	h.footstep.connect(func() -> void: _steps += 1)
	h.set_layers(1 | 2)
	h.show_knob(true)
	h.show_handset(true)
	h.show_knob(false)
	h.show_handset(false)
	var head: Node3D = h.get_node("hips/torso/head")
	var wr_l: Node3D = h.get_node("hips/torso/sh_l/el_l/wr_l")
	for p: String in ["idle", "walk", "reach", "hold", "push", "pull", "pocket", "pat", "thud", "phone", "bogus", "idle"]:
		h.pose = p
		h.walk_speed = 1.4 if p == "walk" else 0.0
		for i in 20:
			h._process(0.1)
		var ear := head.global_transform * Vector3(0.11, 0.12, 0)
		var lh := wr_l.global_transform * Vector3(0.03, -0.07, -0.02)
		print("%-6s hand=%s  hand-ear=%.3f  head=%s  lhand=%s" % [p, h.right_hand_global(), h.right_hand_global().distance_to(ear), head.rotation, lh])
	var tris := 0
	for c in h.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh is ArrayMesh and mi.mesh.get_surface_count() > 0:
			tris += (mi.mesh as ArrayMesh).surface_get_array_index_len(0) / 3
	print("body triangles (lofted meshes, props excluded): ", tris)
	print("footsteps over 2 s at 1.4 m/s: ", _steps, " (expected ~", int(1.4 * 2.0 / 0.62), ")")
	# walking at 2.5 m/s: how far does the left foot move over its flat-footed stance (should be ~0)
	h.pose = "walk"
	h.walk_speed = 2.5
	var an_l: Node3D = h.get_node("hips/hip_l/kn_l/an_l")
	var first := Vector3.INF
	var last := Vector3.ZERO
	var drifts: Array[float] = []
	for i in 720:
		h.position.z -= 2.5 / 240.0
		var t_before: float = h._time
		h._process(1.0 / 240.0)
		if h._time == t_before:
			continue  # only sample right after a 30 Hz pose update
		var q := fposmod(h._phase, TAU)
		if q > 0.5 and q < 1.85:   # foot flat (between heel strike roll and heel off)
			if first == Vector3.INF:
				first = an_l.global_position
			last = an_l.global_position
		elif first != Vector3.INF:
			drifts.append(Vector2(last.x - first.x, last.z - first.z).length())
			first = Vector3.INF
	print("planted-foot drift over each flat stance at 2.5 m/s (m): ", drifts)
	h.position = Vector3.ZERO
	h.walk_speed = 0.0
	h.has_look = true
	h.look_target = Vector3(3, 1.0, -1)
	for i in 10:
		h._process(0.1)
	print("look head rot: ", head.rotation)
	var top := 0.0
	for c in h.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var aabb := mi.global_transform * mi.get_aabb()
		top = maxf(top, aabb.end.y)
	h.pose = "idle"
	print("height approx: ", top)
	print("HUMAN OK")
	return true
