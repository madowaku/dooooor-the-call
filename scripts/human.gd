class_name Human
extends Node3D
## Procedural low-poly protagonist (beige coat). Faces -Z, feet at y=0, ~1.70 m.
## Joint targets are computed from `pose` and applied at 15 Hz so the body moves
## in small visible steps, like a budget PS2 character.

signal footstep

const TICK := 1.0 / 15.0
const STEP_LEN := 0.62
const SKIN := Color(0.84, 0.69, 0.55)
const HAIR := Color(0.11, 0.10, 0.09)
const SHOE := Color(0.13, 0.10, 0.08)
const BRASS := Color(0.78, 0.60, 0.25)
const BLACK := Color(0.05, 0.05, 0.05)
const JOINTS := ["hips", "torso", "head", "sh_r", "el_r", "wr_r", "sh_l", "el_l", "wr_l",
	"hip_r", "kn_r", "an_r", "hip_l", "kn_l", "an_l"]

var pose: String = "idle"
var walk_speed: float = 0.0
var has_look: bool = false
var look_target: Vector3 = Vector3.ZERO

var _j: Dictionary = {}          # name -> Node3D
var _cur: Dictionary = {}        # name -> Vector3 (rotation) ; plus "hips_pos", "torso_pos"
var _meshes: Array[MeshInstance3D] = []
var _palm_r: Node3D
var _knob: Node3D
var _handset: Node3D
var _acc: float = 0.0
var _time: float = 0.0
var _phase: float = 0.0
var _last_pose: String = ""
var _blend_left: float = 0.0
var _shift: float = 0.0
var _shift_target: float = 0.0
var _shift_timer: float = 3.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 2004
	var coat := _mat(Color(1, 1, 1), "res://assets/tex/coat.png")
	var trousers := _mat(Color(1, 1, 1), "res://assets/tex/trousers.png")
	var skin := _mat(SKIN)
	var hair := _mat(HAIR)
	var shoe := _mat(SHOE)

	var hips := _joint("hips", self, Vector3(0, 0.90, 0))
	_box(hips, Vector3(0.42, 0.36, 0.25), Vector3(0, -0.16, 0.005), coat, 2)  # coat skirt
	var torso := _joint("torso", hips, Vector3.ZERO)
	_box(torso, Vector3(0.40, 0.50, 0.23), Vector3(0, 0.25, 0), coat, 3)
	var head := _joint("head", torso, Vector3(0, 0.56, 0))
	_box(head, Vector3(0.08, 0.08, 0.08), Vector3(0, -0.02, 0), skin)  # neck
	_box(head, Vector3(0.20, 0.23, 0.21), Vector3(0, 0.125, 0), skin, 2)
	_box(head, Vector3(0.215, 0.045, 0.225), Vector3(0, 0.235, 0.004), hair)
	_box(head, Vector3(0.215, 0.15, 0.05), Vector3(0, 0.18, 0.09), hair)
	var face := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.19, 0.21)
	face.mesh = fq
	face.material_override = _mat(Color(1, 1, 1), "res://assets/tex/face.png")
	face.position = Vector3(0, 0.12, -0.107)
	face.rotation.y = PI  # QuadMesh faces +Z; turn it to face -Z
	head.add_child(face)
	_meshes.append(face)

	for side: int in [1, -1]:
		var s := "_r" if side > 0 else "_l"
		var sh := _joint("sh" + s, torso, Vector3(0.245 * side, 0.47, 0))
		_box(sh, Vector3(0.09, 0.28, 0.10), Vector3(0, -0.13, 0), coat, 2)
		var el := _joint("el" + s, sh, Vector3(0, -0.28, 0))
		_box(el, Vector3(0.08, 0.25, 0.09), Vector3(0, -0.12, 0), coat, 2)
		var wr := _joint("wr" + s, el, Vector3(0, -0.25, 0))
		_box(wr, Vector3(0.045, 0.10, 0.075), Vector3(0, -0.05, -0.005), skin)
		var hp := _joint("hip" + s, hips, Vector3(0.10 * side, 0, 0))
		_box(hp, Vector3(0.14, 0.42, 0.15), Vector3(0, -0.21, 0), trousers, 2)
		var kn := _joint("kn" + s, hp, Vector3(0, -0.42, 0))
		_box(kn, Vector3(0.115, 0.40, 0.125), Vector3(0, -0.20, 0), trousers, 2)
		var an := _joint("an" + s, kn, Vector3(0, -0.40, 0))
		_box(an, Vector3(0.11, 0.07, 0.24), Vector3(0, -0.045, -0.05), shoe)

	var wr_r: Node3D = _j["wr_r"]
	_palm_r = Node3D.new()
	_palm_r.position = Vector3(-0.03, -0.07, -0.02)
	wr_r.add_child(_palm_r)
	# Brass knob: stem + squashed 6-sided ball.
	_knob = Node3D.new()
	_palm_r.add_child(_knob)
	var brass := _mat(BRASS, "res://assets/tex/brass.png")
	var stem := CylinderMesh.new()
	stem.top_radius = 0.008
	stem.bottom_radius = 0.008
	stem.height = 0.045
	stem.radial_segments = 6
	stem.rings = 0
	_add_mesh(_knob, stem, brass, Vector3(0, 0, 0)).rotation.z = PI * 0.5
	var ball := SphereMesh.new()
	ball.radius = 0.035
	ball.height = 0.045
	ball.radial_segments = 6
	ball.rings = 3
	_add_mesh(_knob, ball, brass, Vector3(-0.03, 0, 0)).rotation.z = PI * 0.5
	_knob.visible = false
	# Telephone handset: bar with two blobs, held along the forearm.
	_handset = Node3D.new()
	_palm_r.add_child(_handset)
	var black := _mat(BLACK)
	_box(_handset, Vector3(0.03, 0.2, 0.04), Vector3.ZERO, black)
	_box(_handset, Vector3(0.06, 0.05, 0.06), Vector3(-0.015, 0.09, 0), black)
	_box(_handset, Vector3(0.06, 0.05, 0.06), Vector3(-0.015, -0.09, 0), black)
	_handset.visible = false

	# Blob shadow stays on the floor under the root.
	var blob := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.8, 0.8)
	blob.mesh = pm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_texture = _tex("res://assets/tex/blob.png")
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bm.render_priority = -1
	blob.material_override = bm
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.02
	add_child(blob)

	for n: String in JOINTS:
		_cur[n] = Vector3.ZERO
	_cur["hips_pos"] = Vector3(0, 0.90, 0)
	_cur["torso_pos"] = Vector3.ZERO
	_apply(_targets())


func show_knob(on: bool) -> void:
	_knob.visible = on


func show_handset(on: bool) -> void:
	_handset.visible = on


func set_layers(mask: int) -> void:
	for m: MeshInstance3D in _meshes:
		m.layers = mask


func right_hand_global() -> Vector3:
	if is_inside_tree():
		return _palm_r.global_position
	var t := _palm_r.transform
	var n := _palm_r.get_parent() as Node3D
	while n != null:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t.origin


func _process(delta: float) -> void:
	if pose == "walk":
		var before := floorf(_phase / PI)
		_phase += walk_speed * delta * PI / STEP_LEN
		if floorf(_phase / PI) != before:
			footstep.emit()
	_acc += delta
	if _acc > 0.5:
		_acc = TICK
	while _acc >= TICK:
		_acc -= TICK
		_tick()


func _tick() -> void:
	_time += TICK
	if pose != _last_pose:
		_last_pose = pose
		_blend_left = 0.7
	_shift_timer -= TICK
	if _shift_timer <= 0.0:
		_shift_timer = _rng.randf_range(3.0, 6.0)
		_shift_target = -_shift_target if absf(_shift_target) > 0.001 else 1.0
	_shift = move_toward(_shift, _shift_target, TICK * 1.5)
	var tg := _targets()
	var k := 1.0
	if _blend_left > 0.0:
		_blend_left -= TICK
		k = 0.45
	for key: String in _cur:
		_cur[key] = (_cur[key] as Vector3).lerp(tg[key], k)
	_apply(_cur)


func _targets() -> Dictionary:
	var t := {}
	for n: String in JOINTS:
		t[n] = Vector3.ZERO
	var hips_y := 0.90
	var torso_pos := Vector3.ZERO
	var head_tilt := 0.0
	var head_pitch := 0.0
	var head_yaw := 0.0
	# Default: arms hanging slightly away from the body, elbows a touch soft.
	t["sh_r"] = Vector3(0.02, 0, 0.07)
	t["sh_l"] = Vector3(0.02, 0, -0.07)
	t["el_r"] = Vector3(0.10, 0, 0)
	t["el_l"] = Vector3(0.10, 0, 0)
	match pose:
		"walk":
			var s := sin(_phase)
			var swing := 0.45
			t["hip_l"] = Vector3(swing * s, 0, 0)
			t["hip_r"] = Vector3(-swing * s, 0, 0)
			var kl := -0.05 - 0.75 * maxf(0.0, cos(_phase - 0.5))
			var kr := -0.05 - 0.75 * maxf(0.0, cos(_phase - 0.5 + PI))
			t["kn_l"] = Vector3(kl, 0, 0)
			t["kn_r"] = Vector3(kr, 0, 0)
			t["an_l"] = Vector3(-(swing * s + kl) * 0.5, 0, 0)
			t["an_r"] = Vector3(-(-swing * s + kr) * 0.5, 0, 0)
			hips_y = 0.885 + 0.03 * (1.0 - absf(s))
			t["sh_r"] = Vector3(0.20 * s, 0, 0.06)
			t["sh_l"] = Vector3(-0.20 * s, 0, -0.06)
			t["el_r"] = Vector3(0.25 + 0.05 * maxf(0.0, s), 0, 0)
			t["el_l"] = Vector3(0.25 + 0.05 * maxf(0.0, -s), 0, 0)
			t["torso"] = Vector3(0.015, 0.06 * s, 0)  # too upright, tiny twist
			head_yaw = -0.04 * s
		"reach":
			t["sh_r"] = Vector3(1.15, 0, 0.02)
			t["el_r"] = Vector3(0.35, 0, 0)
			t["wr_r"] = Vector3(-0.2, 0, 0)
			head_pitch = -0.18
		"hold":
			t["sh_r"] = Vector3(1.0, 0, -0.08)
			t["el_r"] = Vector3(0.5, 0, 0)
			t["sh_l"] = Vector3(0.5, 0, 0.10)
			t["el_l"] = Vector3(0.6, 0, 0)
			t["torso"] = Vector3(-0.07, 0, 0)
			head_pitch = -0.12
		"pocket":
			t["sh_r"] = Vector3(0.75, 0, -0.12)
			t["el_r"] = Vector3(1.25, 0, 0)
			t["wr_r"] = Vector3(0, -1.4, 0)  # twist the palm up
			head_pitch = -0.55
		"pat":
			t["sh_r"] = Vector3(-0.1, 0, 0.2)  # elbow drawn back so the hand lands on the hip pocket
			t["el_r"] = Vector3(0.9 + 0.15 * sin(_time * TAU * 4.0), 0, 0)
			head_pitch = -0.35
			head_yaw = -0.35
		"thud":
			t["sh_r"] = Vector3(1.2, 0, -0.05)
			t["sh_l"] = Vector3(1.2, 0, 0.05)
			t["el_r"] = Vector3(0.3, 0, 0)
			t["el_l"] = Vector3(0.3, 0, 0)
			t["wr_r"] = Vector3(-1.1, 0, 0)
			t["wr_l"] = Vector3(-1.1, 0, 0)
			t["torso"] = Vector3(-0.08, 0, 0)
		"phone":
			# Forearm shorter than real life, so the upper arm rises a bit more than a real one would.
			t["sh_r"] = Vector3(0.7, 0.6, 0.65)
			t["el_r"] = Vector3(2.6, 0, 0)
			t["wr_r"] = Vector3(0, -0.4, 0)
			head_tilt = -0.12
		_:  # idle: nearly frozen, slow breathing, occasional weight shift
			torso_pos.y = 0.006 * sin(_time * TAU / 4.5)
			t["hips"] = Vector3(0, 0, 0.025 * _shift)
			t["torso"] = Vector3(0, 0, -0.025 * _shift)
			t["hip_r"] = Vector3(0, 0, -0.025 * _shift)
			t["hip_l"] = Vector3(0, 0, -0.025 * _shift)
	if has_look and is_inside_tree():
		var d := to_local(look_target) - Vector3(0, 1.55, 0)
		head_yaw = clampf(atan2(-d.x, -d.z), deg_to_rad(-70.0), deg_to_rad(70.0))
		head_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), deg_to_rad(-30.0), deg_to_rad(30.0))
	var torso_rot: Vector3 = t["torso"]
	t["head"] = Vector3(head_pitch - torso_rot.x, head_yaw - torso_rot.y, head_tilt)
	t["hips_pos"] = Vector3(0.012 * _shift if pose == "idle" else 0.0, hips_y, 0)
	t["torso_pos"] = torso_pos
	return t


func _apply(v: Dictionary) -> void:
	for n: String in JOINTS:
		(_j[n] as Node3D).rotation = v[n]
	(_j["hips"] as Node3D).position = v["hips_pos"]
	(_j["torso"] as Node3D).position = v["torso_pos"]


func _joint(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = pos
	parent.add_child(j)
	_j[n] = j
	return j


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, subdiv: int = 0) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	b.subdivide_height = subdiv
	return _add_mesh(parent, b, m, pos)


func _add_mesh(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


func _mat(c: Color, tex_path: String = "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if tex_path != "":
		m.albedo_texture = _tex(tex_path)
	return m


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	push_warning("Human: missing texture " + path)
	return null
