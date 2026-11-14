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
	for p: String in ["idle", "walk", "reach", "hold", "pocket", "pat", "thud", "phone", "idle"]:
		h.pose = p
		h.walk_speed = 1.4 if p == "walk" else 0.0
		for i in 20:
			h._process(0.1)
		var ear := head.global_transform * Vector3(0.11, 0.12, 0)
		print("%-6s hand=%s  hand-ear=%.3f  head=%s" % [p, h.right_hand_global(), h.right_hand_global().distance_to(ear), head.rotation])
	print("footsteps over 2 s at 1.4 m/s: ", _steps, " (expected ~", int(1.4 * 2.0 / 0.62), ")")
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
