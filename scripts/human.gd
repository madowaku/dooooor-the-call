class_name Human
extends Node3D
## Procedural low-poly protagonist (beige coat). Faces -Z, feet at y=0, ~1.70 m.
## Every body segment is a small lofted mesh (6-8 sided rings) built in code, one
## rigid mesh per joint, no skinning: the joint seams are hidden by overlap and
## tapered ends, like an early PS2 character. Joint targets are computed from
## `pose` and applied at 30 Hz with plain linear blending, so the body still moves
## in small, slightly mechanical steps.

signal footstep

const TICK := 1.0 / 30.0
const STEP_LEN := 0.62
const THIGH := 0.42
const SHIN := 0.40
const ANKLE_Y := 0.08
const BRASS := Color(0.78, 0.60, 0.25)
const BLACK := Color(0.05, 0.05, 0.05)
const JOINTS := ["hips", "torso", "head", "sh_r", "el_r", "wr_r", "sh_l", "el_l", "wr_l",
	"hip_r", "kn_r", "an_r", "hip_l", "kn_l", "an_l"]
## u of the 8 head columns (back, right-back, right, right-front, front, ...): the
## face gets most of the 64 px of human_face.png, the back of the head very little.
const FACE_U := [0.0, 0.04, 0.10, 0.28, 0.5, 0.72, 0.90, 0.96, 1.0]
## shoe cross-section (unit x / y), clockwise from the top seen from the toe
const SHOE_PROFILE := [Vector2(0.5, 1.0), Vector2(1.0, 0.1), Vector2(0.75, -1.0),
	Vector2(-0.75, -1.0), Vector2(-1.0, 0.1), Vector2(-0.5, 1.0)]
const SHOE_U := [0.0, 0.17, 0.34, 0.66, 0.83, 0.92, 1.0]
## hat band base height on the head joint, and its forward tip (negative = brim front down)
const HAT_Y := 0.181
const HAT_TILT := -0.11

var pose: String = "idle"
var walk_speed: float = 0.0
var has_look: bool = false
var look_target: Vector3 = Vector3.ZERO

var _j: Dictionary = {}          # name -> Node3D
var _cur: Dictionary = {}        # name -> Vector3 (rotation) ; plus "hips_pos", "torso_pos"
var _meshes: Array[MeshInstance3D] = []
var _skirt_r: Node3D
var _skirt_l: Node3D
var _palm_r: Node3D
var _knob: Node3D
var _handset: Node3D
var _acc: float = 0.0
var _time: float = 0.0
var _phase: float = 0.0
var _last_pose: String = ""
var _pose_t: float = 0.0
var _blend_left: float = 0.0
var _shift: float = 0.0
var _shift_target: float = 0.0
var _shift_timer: float = 3.0
var _rng := RandomNumberGenerator.new()


## Tiny mesh builder: lofted ring grids plus loose triangles, smooth per-vertex normals.
class MB:
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, n: Vector3, uv: Vector2) -> int:
		pts.append(p)
		nrm.append(n)
		uvs.append(uv)
		return pts.size() - 1

	## Godot front faces are clockwise; orient every triangle against its vertex normals.
	func tri(a: int, b: int, c: int) -> void:
		var f := (pts[b] - pts[a]).cross(pts[c] - pts[a])
		if f.length_squared() < 1e-14:
			return
		if f.dot(nrm[a] + nrm[b] + nrm[c]) > 0.0:
			idx.append_array(PackedInt32Array([a, c, b]))
		else:
			idx.append_array(PackedInt32Array([a, b, c]))

	## convex polygon (fan) with one flat normal facing roughly `out_hint`
	func flat(p: Array, uv: Array, out_hint: Vector3, soften := Vector3.ZERO) -> void:
		var n: Vector3 = ((p[1] as Vector3) - p[0]).cross((p[2] as Vector3) - p[0]).normalized()
		if n.dot(out_hint) < 0.0:
			n = -n
		n = (n + soften).normalized()  # bend small details' normals toward the surface they sit on
		var ids: Array[int] = []
		for i in p.size():
			ids.append(add(p[i], n, uv[i]))
		for i in range(1, p.size() - 1):
			tri(ids[0], ids[i], ids[i + 1])

	## small faceted wedge / pyramid: each face gets its own normal pointing away from `inner`
	func wedge(faces: Array, uv: Vector2, inner: Vector3, soften := Vector3.ZERO) -> void:
		for f: Array in faces:
			var c: Vector3 = ((f[0] as Vector3) + f[1] + f[2]) / 3.0
			flat(f, [uv, uv + Vector2(0.01, 0), uv + Vector2(0, 0.01)], c - inner, soften)

	## rings: Array of PackedVector3Array (same point count). closed: wrap around.
	## us: one u per column (point count + 1 when closed). vs: one v per ring.
	func loft(rings: Array, us: Array, vs: Array, closed: bool, centers: Array = []) -> void:
		var R := rings.size()
		var m: int = (rings[0] as PackedVector3Array).size()
		var cols := m + 1 if closed else m
		var cen: Array[Vector3] = []
		for r in R:
			if centers.size() > 0:
				cen.append(centers[r])
			else:
				var c := Vector3.ZERO
				for p: Vector3 in rings[r]:
					c += p
				cen.append(c / float(m))
		var base := pts.size()
		for r in R:
			var ring: PackedVector3Array = rings[r]
			var r0 := maxi(r - 1, 0)
			var r1 := mini(r + 1, R - 1)
			for j in cols:
				var i := j % m
				var p := ring[i]
				var prv := (i - 1 + m) % m if closed else maxi(i - 1, 0)
				var nxt := (i + 1) % m if closed else mini(i + 1, m - 1)
				var tng := ring[nxt] - ring[prv]
				var alg: Vector3 = (rings[r1] as PackedVector3Array)[i] - (rings[r0] as PackedVector3Array)[i]
				var out := p - cen[r]
				if out.length_squared() < 1e-8:  # pole: point along the axis
					out = p - cen[r1 if r1 != r else r0]
				var n := tng.cross(alg)
				if n.length_squared() < 1e-12:
					n = out
				elif n.dot(out) < 0.0:
					n = -n
				add(p, n.normalized(), Vector2(us[j], vs[r]))
		for r in R - 1:
			for j in cols - 1:
				var a := base + r * cols + j
				tri(a, a + 1, a + cols + 1)
				tri(a, a + cols + 1, a + cols)

	func build() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pts
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return am


func _init() -> void:
	_rng.seed = 2004
	var coat := _mat("res://assets/tex/human_coat.png")
	var sleeve := _mat("res://assets/tex/human_sleeve.png")
	var trousers := _mat("res://assets/tex/human_trousers.png")
	var face := _mat("res://assets/tex/human_face.png")
	var hair := _mat("res://assets/tex/human_hair.png")
	var skin := _mat("res://assets/tex/human_skin.png")
	var shoe := _mat("res://assets/tex/human_shoe.png")
	var hat := _mat("res://assets/tex/human_hat.png")

	var hips := _joint("hips", self, Vector3(0, 0.90, 0))
	_mesh(hips, _build_hip_block(), coat)
	_skirt_r = Node3D.new()
	_skirt_r.name = "skirt_r"
	hips.add_child(_skirt_r)
	_mesh(_skirt_r, _build_skirt(1.0), coat)
	_skirt_l = Node3D.new()
	_skirt_l.name = "skirt_l"
	hips.add_child(_skirt_l)
	_mesh(_skirt_l, _build_skirt(-1.0), coat)
	var torso := _joint("torso", hips, Vector3.ZERO)
	_mesh(torso, _build_torso(), coat)
	var head := _joint("head", torso, Vector3(0, 0.56, 0))
	_mesh(head, _build_head(), face)
	_mesh(head, _build_hair(), hair)
	# old felt hat, a size too big, sitting low and tipped forward so the brim hides the eyes
	var hat_mi := _add_mesh(head, _build_hat(), hat, Vector3(0, HAT_Y, 0.002))
	hat_mi.rotation = Vector3(HAT_TILT, 0, 0.025)

	for side: float in [1.0, -1.0]:
		var s := "_r" if side > 0 else "_l"
		var sh := _joint("sh" + s, torso, Vector3(0.245 * side, 0.47, 0))
		_mesh(sh, _build_upper_arm(side), sleeve)
		var el := _joint("el" + s, sh, Vector3(0, -0.28, 0))
		_mesh(el, _build_forearm(side), sleeve)
		var wr := _joint("wr" + s, el, Vector3(0, -0.25, 0))
		_mesh(wr, _build_hand(side), skin)
		var hp := _joint("hip" + s, hips, Vector3(0.10 * side, 0, 0))
		_mesh(hp, _build_thigh(side), trousers)
		var kn := _joint("kn" + s, hp, Vector3(0, -THIGH, 0))
		_mesh(kn, _build_shin(side), trousers)
		var an := _joint("an" + s, kn, Vector3(0, -SHIN, 0))
		_mesh(an, _build_shoe(side), shoe)

	var wr_r: Node3D = _j["wr_r"]
	_palm_r = Node3D.new()
	_palm_r.position = Vector3(-0.03, -0.07, -0.02)
	wr_r.add_child(_palm_r)
	# Brass knob: stem + squashed 6-sided ball.
	_knob = Node3D.new()
	_palm_r.add_child(_knob)
	var brass := _mat("res://assets/tex/brass.png", BRASS)
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
	var black := _mat("", BLACK)
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
	var t0 := _targets()
	for key: String in t0:
		_cur[key] = t0[key]
	_apply(_cur)


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
	_pose_t += TICK
	if pose != _last_pose:
		_last_pose = pose
		_blend_left = 0.7
		_pose_t = 0.0
	_shift_timer -= TICK
	if _shift_timer <= 0.0:
		_shift_timer = _rng.randf_range(3.0, 6.0)
		_shift_target = -_shift_target if absf(_shift_target) > 0.001 else 1.0
	_shift = move_toward(_shift, _shift_target, TICK * 1.5)
	var tg := _targets()
	var k := 1.0
	if _blend_left > 0.0:
		_blend_left -= TICK
		k = 0.26  # same settle time as 0.45 per tick at the old 15 Hz
	for key: String in _cur:
		_cur[key] = (_cur[key] as Vector3).lerp(tg[key], k)
	_apply(_cur)


# ------------------------------------------------------------------ poses

func _targets() -> Dictionary:
	var t := {}
	for n: String in JOINTS:
		t[n] = Vector3.ZERO
	var hp := Vector3(0, 0.893, 0)
	var torso_pos := Vector3.ZERO
	var head_tilt := 0.0
	var head_pitch := 0.0
	var head_yaw := 0.0
	var foot_r := Vector3(0.11, ANKLE_Y, 0.0)
	var foot_l := Vector3(-0.11, ANKLE_Y, 0.0)
	var pitch_r := 0.0
	var pitch_l := 0.0
	var strain := sin(_time * TAU * 0.55)
	# Default: arms hanging slightly away from the body, elbows a touch soft.
	t["sh_r"] = Vector3(0.03, 0, 0.07)
	t["sh_l"] = Vector3(0.03, 0, -0.07)
	t["el_r"] = Vector3(0.14, 0, 0)
	t["el_l"] = Vector3(0.14, 0, 0)
	match pose:
		"walk":
			# heel strike of the left foot at phase 0, right at PI (footstep fires on both)
			var ph := _phase
			var a := clampf(walk_speed / 1.4, 0.5, 1.8)
			var s := sin(ph)
			var c := cos(ph)
			hp = Vector3(-0.018 * s, 0.866 + 0.024 * absf(s) - 0.012 * maxf(a - 1.0, 0.0), 0)
			t["hips"] = Vector3(-0.02 * a, -0.08 * c, -0.035 * s)
			t["torso"] = Vector3(-0.02 * a, 0.13 * c, 0.03 * s)
			var fl := _foot_cycle(ph)
			var fr := _foot_cycle(ph + PI)
			foot_l = Vector3(-0.095, fl[0], fl[1])
			pitch_l = fl[2]
			foot_r = Vector3(0.095, fr[0], fr[1])
			pitch_r = fr[2]
			var ca := cos(ph - 0.35)  # arms trail the legs a little
			var sw := minf(0.24 * a + 0.06, 0.55)
			t["sh_r"] = Vector3(0.04 + sw * ca, 0, 0.08)
			t["sh_l"] = Vector3(0.04 - sw * ca, 0, -0.08)
			t["el_r"] = Vector3(0.22 + 0.6 * sw * maxf(0.0, ca), 0, 0)
			t["el_l"] = Vector3(0.22 + 0.6 * sw * maxf(0.0, -ca), 0, 0)
			t["wr_r"] = Vector3(0.05, 0, 0)
			t["wr_l"] = Vector3(0.05, 0, 0)
		"reach":
			t["sh_r"] = Vector3(1.15, 0, 0.02)
			t["el_r"] = Vector3(0.35, 0, 0)
			t["wr_r"] = Vector3(-0.2, 0, 0)
			t["sh_l"] = Vector3(0.12, 0, -0.08)
			t["el_l"] = Vector3(0.25, 0, 0)
			foot_l.z = -0.07
			head_pitch = -0.18
		"hold":
			# both hands on the knob side, body square to the door
			t["sh_r"] = Vector3(1.0, 0, -0.08)
			t["el_r"] = Vector3(0.5, 0, 0)
			t["sh_l"] = Vector3(0.95, 0.0, 0.48)
			t["el_l"] = Vector3(0.55, 0, 0)
			t["wr_l"] = Vector3(-0.2, 0, 0)
			t["torso"] = Vector3(-0.07, 0, 0)
			hp.y = 0.885
			foot_r = Vector3(0.13, ANKLE_Y, 0.02)
			foot_l = Vector3(-0.13, ANKLE_Y, 0.02)
			head_pitch = -0.12
		"push":
			# leaning into a heavy leaf: ~12 degrees forward, back leg long, arms nearly straight
			var e := 0.012 * strain
			t["hips"] = Vector3(-0.08 - e, 0, 0)
			t["torso"] = Vector3(-0.13 - e, 0, 0)
			hp = Vector3(0, 0.855, 0.075)
			foot_l = Vector3(-0.12, ANKLE_Y, -0.10)
			foot_r = Vector3(0.12, ANKLE_Y + 0.03, 0.42)
			pitch_r = -0.45
			t["sh_r"] = Vector3(1.40 + e, 0, -0.06)
			t["el_r"] = Vector3(0.12, 0, 0)
			t["wr_r"] = Vector3(-0.8, 0, 0)
			t["sh_l"] = Vector3(1.38 + e, 0, 0.30)
			t["el_l"] = Vector3(0.14, 0, 0)
			t["wr_l"] = Vector3(-0.8, 0, 0)
			head_pitch = 0.08
		"pull":
			# leaning back ~10 degrees, knees bent, arms drawn in
			var e2 := 0.012 * strain
			t["hips"] = Vector3(0.05 + e2, 0, 0)
			t["torso"] = Vector3(0.125 + e2, 0, 0)
			hp = Vector3(0, 0.835, 0.02)
			foot_l = Vector3(-0.13, ANKLE_Y, -0.12)
			foot_r = Vector3(0.13, ANKLE_Y, 0.10)
			t["sh_r"] = Vector3(0.52 - e2, 0, -0.04)
			t["el_r"] = Vector3(0.85, 0, 0)
			t["wr_r"] = Vector3(0.15, -0.5, 0)
			t["sh_l"] = Vector3(0.50 - e2, 0, 0.30)
			t["el_l"] = Vector3(0.9, 0, 0)
			t["wr_l"] = Vector3(0.15, 0.3, 0)
			head_pitch = -0.05
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
			# palms flat on the blank leaf; a short lunge that settles back
			var lunge := 1.0 if _pose_t < 0.3 else 0.0
			t["hips"] = Vector3(-0.05 * lunge, 0, 0)
			hp.z = -0.03 * lunge
			t["sh_r"] = Vector3(1.2, 0, -0.05)
			t["sh_l"] = Vector3(1.2, 0, 0.05)
			t["el_r"] = Vector3(0.3, 0, 0)
			t["el_l"] = Vector3(0.3, 0, 0)
			t["wr_r"] = Vector3(-1.1, 0, 0)
			t["wr_l"] = Vector3(-1.1, 0, 0)
			t["torso"] = Vector3(-0.08, 0, 0)
			foot_r.z = -0.06 * lunge
		"phone":
			# Forearm shorter than real life, so the upper arm rises a bit more than a real one would.
			t["sh_r"] = Vector3(0.7, 0.6, 0.65)
			t["el_r"] = Vector3(2.6, 0, 0)
			t["wr_r"] = Vector3(0, -0.4, 0)
			head_tilt = -0.12
		_:  # idle: nearly frozen, slow breathing, occasional weight shift, eyes drifting
			var br := sin(_time * TAU / 4.5)
			torso_pos.y = 0.006 * br
			hp = Vector3(0.022 * _shift, 0.893, 0)
			t["hips"] = Vector3(0, 0, 0.03 * _shift)
			t["torso"] = Vector3(0.01 * br, 0, -0.035 * _shift)
			foot_r.z = -0.035 * maxf(0.0, -_shift)  # unloaded foot rests a little forward
			foot_l.z = -0.035 * maxf(0.0, _shift)
			t["sh_r"] = Vector3(0.03 - 0.01 * br, 0, 0.07)
			t["sh_l"] = Vector3(0.03 - 0.01 * br, 0, -0.07)
			head_yaw = 0.06 * sin(_time * 0.41) + 0.025 * sin(_time * 1.13)
			head_pitch = -0.03 + 0.02 * sin(_time * 0.29)
	var hips_rot: Vector3 = t["hips"]
	if has_look and is_inside_tree():
		var d := to_local(look_target) - Vector3(0, 1.55, 0)
		head_yaw = clampf(atan2(-d.x, -d.z), deg_to_rad(-70.0), deg_to_rad(70.0))
		head_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), deg_to_rad(-30.0), deg_to_rad(30.0))
		var over := absf(head_yaw) - deg_to_rad(45.0)
		if over > 0.0:  # big turns bring the shoulders along a little
			var tr: Vector3 = t["torso"]
			tr.y += over * 0.45 * signf(head_yaw)
			t["torso"] = tr
	var torso_rot: Vector3 = t["torso"]
	t["head"] = Vector3(head_pitch - torso_rot.x - hips_rot.x, head_yaw - torso_rot.y - hips_rot.y,
		head_tilt - torso_rot.z - hips_rot.z)
	_leg(t, "_r", 1.0, hp, foot_r, pitch_r)
	_leg(t, "_l", -1.0, hp, foot_l, pitch_l)
	t["hips_pos"] = hp
	t["torso_pos"] = torso_pos
	return t


## Two-bone leg IK in the hips frame: puts the ankle on `foot` (root space) and gives
## the shoe the pitch `pitch` (positive = toes up).
func _leg(t: Dictionary, s: String, side: float, hp: Vector3, foot: Vector3, pitch: float) -> void:
	var hr: Vector3 = t["hips"]
	var b := Basis.from_euler(hr)
	var v := b.inverse() * (foot - (hp + b * Vector3(0.10 * side, 0, 0)))
	var rz := atan2(v.x, -v.y)
	var down := sqrt(v.x * v.x + v.y * v.y)
	var fwd := -v.z
	var dd := clampf(sqrt(down * down + fwd * fwd), 0.3, THIGH + SHIN - 0.002)
	var beta := atan2(fwd, down)
	var ca := clampf((THIGH * THIGH + dd * dd - SHIN * SHIN) / (2.0 * THIGH * dd), -1.0, 1.0)
	var ck := clampf((THIGH * THIGH + SHIN * SHIN - dd * dd) / (2.0 * THIGH * SHIN), -1.0, 1.0)
	var hx := beta + acos(ca)
	var kx := -(PI - acos(ck))
	t["hip" + s] = Vector3(hx, 0, rz)
	t["kn" + s] = Vector3(kx, 0, 0)
	t["an" + s] = Vector3(pitch - (hr.x + hx + kx), 0, -(hr.z + rz))


## stance, t 0..1: heel strike (toes up) -> flat -> heel off (rolling over the toe).
## The ground contact moves back linearly at walking speed, so the foot does not slide.
func _stance(t: float) -> Array:
	var a := STEP_LEN * 0.5
	var z := -a + 2.0 * a * t
	var p := 0.0
	if t < 0.15:
		p = 0.25 * (1.0 - t / 0.15)
	elif t > 0.6:
		p = -0.6 * (t - 0.6) / 0.4
	var piv := Vector3(0, -0.08, 0.06) if p > 0.0 else Vector3(0, -0.08, -0.15)
	var ank := Vector3(0, ANKLE_Y, z) + piv - Basis(Vector3.RIGHT, p) * piv
	return [ank.y, ank.z, p]


func _foot_cycle(q: float) -> Array:
	q = fposmod(q, TAU)
	if q < PI:
		return _stance(q / PI)
	var t := (q - PI) / PI
	var s0 := _stance(1.0)
	var s1 := _stance(0.0)
	var e := (1.0 - cos(PI * t)) * 0.5
	return [lerpf(s0[0], s1[0], t) + 0.055 * sin(PI * t), lerpf(s0[1], s1[1], e), lerpf(s0[2], s1[2], t)]


func _apply(v: Dictionary) -> void:
	for n: String in JOINTS:
		(_j[n] as Node3D).rotation = v[n]
	(_j["hips"] as Node3D).position = v["hips_pos"]
	(_j["torso"] as Node3D).position = v["torso_pos"]
	# coat skirt halves follow the thighs part of the way (split front and back)
	var hr: Vector3 = v["hip_r"]
	var hl: Vector3 = v["hip_l"]
	_skirt_r.rotation = Vector3(clampf(0.55 * hr.x, -0.3, 0.45), 0, 0.5 * hr.z)
	_skirt_l.rotation = Vector3(clampf(0.55 * hl.x, -0.3, 0.45), 0, 0.5 * hl.z)


# ------------------------------------------------------------------ geometry

static func _ring(n: int, y: float, hx: float, hz: float, cx := 0.0, cz := 0.0, k := 1.0, zf := 1.0,
		a0 := 0.0, a1 := TAU, closed := true) -> PackedVector3Array:
	# angle 0 = back (+Z), PI/2 = right (+X), PI = front (-Z)
	var out := PackedVector3Array()
	var cnt := n if closed else n + 1
	for i in cnt:
		var a := a0 + (a1 - a0) * float(i) / float(n)
		var s := sin(a)
		var c := cos(a)
		var f := lerpf(1.0, k, absf(sin(2.0 * a)))
		var z := c * hz * (zf if c < 0.0 else 1.0)
		out.append(Vector3(cx + s * hx * f, y, cz + z * f))
	return out


static func _mirror(r: PackedVector3Array, side: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in r:
		out.append(Vector3(p.x * side, p.y, p.z))
	return out


static func _us(n: int) -> Array:
	var u := []
	for i in n + 1:
		u.append(float(i) / float(n))
	return u


## limb tube along -Y. specs: [y, rx, rz, cx (outward), cz]; rx = rz = 0 makes a pole.
static func _tube(mb: MB, n: int, specs: Array, side: float, v0: float, v1: float, k := 1.0) -> void:
	var rings := []
	var vs := []
	var ytop: float = specs[0][0]
	var ybot: float = specs[specs.size() - 1][0]
	for s: Array in specs:
		rings.append(_mirror(_ring(n, s[0], s[1], s[2], s[3], s[4], k), side))
		vs.append(lerpf(v0, v1, (ytop - s[0]) / (ytop - ybot)))
	mb.loft(rings, _us(n), vs, true)


static func _coat_v(y: float) -> float:
	return 0.045 + (0.58 - y) * 0.92


func _build_torso() -> ArrayMesh:
	var mb := MB.new()
	# y, hx, hz, cz : waist -> chest -> square-ish shoulders -> sloping trapezius -> neck hole
	var spec := [[-0.05, 0.165, 0.118, 0.0], [0.39, 0.205, 0.13, -0.01], [0.485, 0.232, 0.118, 0.0],
		[0.535, 0.188, 0.096, 0.005], [0.572, 0.072, 0.06, 0.008], [0.58, 0.0, 0.0, 0.008]]
	var rings := []
	var vs := []
	for s: Array in spec:
		rings.append(_ring(8, s[0], s[1], s[2], 0.0, s[3], 1.10))
		vs.append(_coat_v(s[0]))
	mb.loft(rings, _us(8), vs, true)
	# stand collar, open in a shallow V at the front
	var lo := _ring(8, 0.528, 0.118, 0.09, 0.0, 0.005, 1.05)
	var hi := _ring(8, 0.588, 0.08, 0.07, 0.0, 0.01, 1.05)
	for i: int in [3, 4, 5]:
		var p := hi[i]
		p.y -= 0.035 if i == 4 else 0.012
		hi[i] = p
	mb.loft([lo, hi], _us(8), [0.045, 0.0], true)
	return mb.build()


func _build_hip_block() -> ArrayMesh:
	var mb := MB.new()
	var a := _ring(8, 0.07, 0.168, 0.12, 0.0, 0.0, 1.08)
	var b := _ring(8, -0.10, 0.188, 0.134, 0.0, 0.004, 1.08)
	mb.loft([a, b], _us(8), [_coat_v(0.07), _coat_v(-0.10)], true)
	return mb.build()


## one half of the coat skirt (side +1 right, -1 left); the halves meet on the x=0 plane
func _build_skirt(side: float) -> ArrayMesh:
	var mb := MB.new()
	var a0 := 0.0 if side > 0 else PI
	var spec := [[-0.03, 0.184, 0.13, 0.004], [-0.20, 0.196, 0.143, 0.008], [-0.43, 0.212, 0.165, 0.012]]
	var rings := []
	var vs := []
	var cen := []
	for s: Array in spec:
		rings.append(_ring(4, s[0], s[1], s[2], 0.0, s[3], 1.05, 1.0, a0, a0 + PI, false))
		vs.append(_coat_v(s[0]))
		cen.append(Vector3(0, s[0], s[3]))
	# front edges ride up a little: the coat hangs open at the bottom
	var hem: PackedVector3Array = rings[2]
	var fi := 4 if side > 0 else 0
	var fp := hem[fi]
	fp.y += 0.025
	hem[fi] = fp
	rings[2] = hem
	var us := []
	for i in 5:
		us.append((a0 + PI * float(i) / 4.0) / TAU)
	mb.loft(rings, us, vs, false, cen)
	# flat inner face on the centre plane (visible as the coat's edge when the halves split)
	var bi := 0 if side > 0 else 4
	for r in 2:
		var p0: PackedVector3Array = rings[r]
		var p1: PackedVector3Array = rings[r + 1]
		mb.flat([p0[fi], p0[bi], p1[bi], p1[fi]],
			[Vector2(0.30, 0.80), Vector2(0.34, 0.80), Vector2(0.34, 0.86), Vector2(0.30, 0.86)],
			Vector3(-side, 0, 0))
	# hem underside (dark lining)
	var mid := (hem[0] + hem[4]) * 0.5
	for i in 4:
		mb.flat([mid, hem[i], hem[i + 1]], [Vector2(0.3, 0.995), Vector2(0.31, 0.995), Vector2(0.32, 0.995)],
			Vector3(0, -1, 0))
	return mb.build()


func _skull(y: float, a: float, grow: float) -> Vector3:
	# interpolated head rings (y, hx, hz, cz) for hair placement
	var tab := [[0.065, 0.072, 0.085, -0.012], [0.12, 0.088, 0.098, 0.0], [0.17, 0.09, 0.102, 0.004],
		[0.218, 0.07, 0.085, 0.008], [0.245, 0.0, 0.0, 0.01]]
	var lo: Array = tab[0]
	var hi: Array = tab[tab.size() - 1]
	for i in tab.size() - 1:
		if y >= tab[i][0] and y <= tab[i + 1][0]:
			lo = tab[i]
			hi = tab[i + 1]
	var f := clampf((y - lo[0]) / maxf(hi[0] - lo[0], 1e-5), 0.0, 1.0)
	var hx := lerpf(lo[1], hi[1], f)
	var hz := lerpf(lo[2], hi[2], f)
	var cz := lerpf(lo[3], hi[3], f)
	var k := lerpf(1.0, 1.06, absf(sin(2.0 * a)))
	return Vector3(sin(a) * (hx * k + grow), y, cz + cos(a) * (hz * k + grow))


func _build_head() -> ArrayMesh:
	var mb := MB.new()
	# y, hx, hz, cz, front-flatten : chin pole, jaw, cheekbones, brow, crown, top pole
	var spec := [[0.022, 0.0, 0.0, -0.05, 1.0], [0.065, 0.072, 0.085, -0.012, 1.0],
		[0.092, 0.08, 0.093, -0.006, 0.98],
		[0.12, 0.088, 0.098, 0.0, 0.97], [0.17, 0.09, 0.102, 0.004, 0.96],
		[0.218, 0.07, 0.085, 0.008, 1.0], [0.245, 0.0, 0.0, 0.01, 1.0]]
	var rings := []
	var vs := []
	for s: Array in spec:
		rings.append(_ring(8, s[0], s[1], s[2], 0.0, s[3], 1.06, s[4]))
		vs.append(_face_v(s[0]))
	# a squarer jaw angle, a hollow under the cheekbone, cheekbones a touch proud
	_scale_pts(rings, 1, [1, 2, 6, 7], Vector3(1.08, 1.0, 1.0))
	_scale_pts(rings, 2, [3, 5], Vector3(0.92, 1.0, 0.95))
	_scale_pts(rings, 3, [3, 5], Vector3(1.04, 1.0, 1.0))
	mb.loft(rings, FACE_U, vs, true)
	# nose wedge
	var nl := Vector3(-0.011, 0.094, -0.094)
	var nr := Vector3(0.011, 0.094, -0.094)
	var nt := Vector3(0.0, 0.138, -0.098)
	var tip := Vector3(0.0, 0.099, -0.113)
	var nuv := Vector2(0.54, _face_v(0.115))
	mb.wedge([[nl, nt, tip], [nt, nr, tip], [nl, tip, nr]], nuv, Vector3(0, 0.11, -0.08), Vector3(0, 0.1, -1.2))
	# ears
	for side: float in [1.0, -1.0]:
		var top := Vector3(0.086 * side, 0.152, 0.016)
		var bot := Vector3(0.083 * side, 0.098, 0.02)
		var bk := Vector3(0.085 * side, 0.13, 0.045)
		var out := Vector3(0.104 * side, 0.128, 0.03)
		var euv := Vector2(0.10 if side > 0 else 0.90, _face_v(0.125))
		mb.wedge([[top, bot, out], [bot, bk, out], [bk, top, out]], euv, Vector3(0.07 * side, 0.125, 0.025))
	# neck (hidden ends inside the head and the collar)
	var neck := []
	for s: Array in [[0.06, 0.044, 0.046], [-0.07, 0.05, 0.052]]:
		neck.append(_ring(6, s[0], s[1], s[2], 0.0, 0.008))
	var nu := []
	for i in 7:
		nu.append(0.14 + 0.2 * float(i) / 6.0)
	mb.loft(neck, nu, [0.93, 0.99], true)
	return mb.build()


static func _face_v(y: float) -> float:
	return 1.0 - (y - 0.015) / 0.23


func _build_hair() -> ArrayMesh:
	var mb := MB.new()
	# Short back and sides showing under the hat; no fringe (the front edge stays inside the crown).
	var edge := [0.072, 0.098, 0.138, 0.176, 0.18, 0.176, 0.138, 0.098]
	var r0 := PackedVector3Array()
	var r1 := PackedVector3Array()
	var r3 := PackedVector3Array()
	for i in 8:
		var a := TAU * float(i) / 8.0
		var front := absi(i - 4) <= 1
		r0.append(_skull(edge[i], a, 0.005 if front else 0.007))
		r1.append(_skull(0.19, a, 0.009))
		r3.append(Vector3(0, 0.222, 0.01))
	mb.loft([r3, r1, r0], _us(8), [0.0, 0.55, 1.0], true)
	return mb.build()


## Worn felt fedora in hat space (origin at the band base, -Z front). The node sits at
## HAT_Y on the head joint, tipped forward by HAT_TILT. v: 0-.18 crown top, .18-.62 crown
## side with the band at .50-.62, .64-.82 brim top, .86-1 brim underside.
func _build_hat() -> ArrayMesh:
	var mb := MB.new()
	var us := _us(8)
	var base := _ring(8, 0.0, 0.106, 0.122, 0.0, 0.004, 1.04)
	var band := _ring(8, 0.032, 0.103, 0.118, 0.0, 0.004, 1.04)
	var top := _ring(8, 0.087, 0.086, 0.104, 0.0, 0.008, 1.0)
	# front pinch: the two front corners squeezed in and down, crown sloping to the front
	for i: int in [3, 5]:
		top[i] = Vector3(top[i].x * 0.74, top[i].y - 0.016, top[i].z * 0.9)
	top[4] = top[4] + Vector3(0, -0.013, 0.006)
	top[2] = top[2] + Vector3(0, -0.004, 0)
	top[6] = top[6] + Vector3(0, -0.004, 0)
	top[0] = top[0] + Vector3(0, 0.003, 0)
	mb.loft([top, band, base], us, [0.18, 0.50, 0.62], true)
	# crown top: a centre crease running front to back (two low points)
	var cf := Vector3(0.0, 0.064, -0.035)
	var cb := Vector3(0.0, 0.071, 0.05)
	var up := Vector3.UP
	for i in 8:
		var j := (i + 1) % 8
		var c := cf if (i >= 2 and i <= 5) else cb
		var cuv := Vector2(0.5, 0.03) if c == cf else Vector2(0.02, 0.03)
		mb.flat([top[i], top[j], c], [Vector2(us[i], 0.17), Vector2(us[i + 1], 0.17), cuv], up)
	mb.flat([top[2], cf, cb], [Vector2(0.25, 0.17), Vector2(0.5, 0.03), Vector2(0.02, 0.03)], up)
	mb.flat([top[6], cb, cf], [Vector2(0.75, 0.17), Vector2(0.02, 0.03), Vector2(0.5, 0.03)], up)
	# brim: oval (wider front and back), snapped down at the front, the back turned up a little
	var outer := PackedVector3Array()
	for i in 8:
		var a := TAU * float(i) / 8.0
		var p := base[i]
		var d := Vector3(p.x, 0, p.z - 0.004).normalized()
		var w := lerpf(0.047, 0.06, absf(cos(a)))
		var y := -0.021 * maxf(0.0, -cos(a)) + 0.012 * maxf(0.0, cos(a)) + 0.006 * sin(a) * sin(a)
		outer.append(p + d * w + Vector3(0, y, 0))
	var under_in := _ring(8, -0.006, 0.09, 0.104, 0.0, 0.004, 1.04)
	var base_t := mb.pts.size()
	for j in 9:
		var i := j % 8
		var d := Vector3(outer[i].x, 0, outer[i].z).normalized()
		mb.add(base[i], Vector3.UP, Vector2(us[j], 0.645))
		mb.add(outer[i], (Vector3.UP + d * 0.35).normalized(), Vector2(us[j], 0.82))
	var base_u := mb.pts.size()
	for j in 9:
		var i := j % 8
		var d := Vector3(outer[i].x, 0, outer[i].z).normalized()
		mb.add(under_in[i], Vector3.DOWN, Vector2(us[j], 0.99))
		mb.add(outer[i] + Vector3(0, -0.005, 0), (Vector3.DOWN + d * 0.35).normalized(), Vector2(us[j], 0.87))
	for j in 8:
		for b: int in [base_t, base_u]:
			var a0 := b + j * 2
			mb.tri(a0, a0 + 1, a0 + 3)
			mb.tri(a0, a0 + 3, a0 + 2)
	return mb.build()


static func _scale_pts(rings: Array, r: int, ids: Array, s: Vector3) -> void:
	var ring: PackedVector3Array = rings[r]
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	for i: int in ids:
		ring[i] = c + (ring[i] - c) * s
	rings[r] = ring


func _build_upper_arm(side: float) -> ArrayMesh:
	var mb := MB.new()
	# rounded cap tucked in under the coat's shoulder line (no shoulder-pad corner on top)
	_tube(mb, 6, [[-0.002, 0.0, 0.0, -0.034, 0.0], [-0.02, 0.036, 0.046, -0.016, 0.0], [-0.075, 0.054, 0.056, 0.004, 0.0],
		[-0.27, 0.046, 0.05, 0.0, 0.004], [-0.305, 0.034, 0.038, 0.0, 0.004]], side, 0.0, 0.47)
	return mb.build()


func _build_forearm(side: float) -> ArrayMesh:
	var mb := MB.new()
	_tube(mb, 6, [[0.035, 0.034, 0.038, 0.0, 0.0], [-0.06, 0.048, 0.05, 0.0, 0.004],
		[-0.255, 0.049, 0.052, 0.0, -0.002]], side, 0.5, 1.0)
	return mb.build()


func _build_hand(side: float) -> ArrayMesh:
	var mb := MB.new()
	# mitten: palm faces the thigh (-x on the right hand), fingers curl toward the palm
	_tube(mb, 6, [[0.03, 0.022, 0.034, 0.0, 0.0], [-0.035, 0.019, 0.046, 0.0, -0.004],
		[-0.085, 0.016, 0.042, -0.005, -0.006], [-0.114, 0.0, 0.0, -0.01, -0.004]], side, 0.0, 1.0)
	var b1 := Vector3(-0.012 * side, -0.012, -0.036)
	var b2 := Vector3(-0.018 * side, -0.042, -0.04)
	var b3 := Vector3(-0.002 * side, -0.036, -0.046)
	var tip := Vector3(-0.022 * side, -0.074, -0.056)
	mb.wedge([[b1, b2, tip], [b2, b3, tip], [b3, b1, tip]], Vector2(0.72, 0.45), Vector3(0, -0.035, -0.03))
	return mb.build()


func _build_thigh(side: float) -> ArrayMesh:
	var mb := MB.new()
	_tube(mb, 6, [[0.0, 0.066, 0.074, -0.01, 0.005], [-0.40, 0.06, 0.066, 0.0, -0.004],
		[-0.45, 0.044, 0.048, 0.0, -0.002]], side, 0.0, 0.5)
	return mb.build()


func _build_shin(side: float) -> ArrayMesh:
	var mb := MB.new()
	_tube(mb, 6, [[0.035, 0.05, 0.054, 0.0, -0.004], [-0.10, 0.058, 0.064, 0.0, 0.01],
		[-0.415, 0.047, 0.052, 0.0, -0.004]], side, 0.5, 1.0)
	return mb.build()


func _build_shoe(side: float) -> ArrayMesh:
	var mb := MB.new()
	# z, hx, cy, top, bottom : heel pole -> heel -> ball -> toe -> toe pole
	var spec := [[0.078, 0.0, -0.045, 0.0, 0.0], [0.06, 0.04, -0.035, 0.038, 0.045],
		[-0.09, 0.05, -0.055, 0.03, 0.025], [-0.15, 0.042, -0.06, 0.02, 0.02], [-0.172, 0.0, -0.063, 0.0, 0.0]]
	var rings := []
	var vs := []
	for s: Array in spec:
		var r := PackedVector3Array()
		for p: Vector2 in SHOE_PROFILE:
			var y: float = s[2] + (p.y * s[3] if p.y > 0.0 else p.y * s[4])
			r.append(Vector3(p.x * s[1] * side, y, s[0]))
		rings.append(r)
		vs.append((0.078 - s[0]) / 0.25)
	mb.loft(rings, SHOE_U, vs, true)
	return mb.build()


# ------------------------------------------------------------------ helpers

func _joint(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = pos
	parent.add_child(j)
	_j[n] = j
	return j


func _mesh(parent: Node3D, mesh: Mesh, m: Material) -> MeshInstance3D:
	return _add_mesh(parent, mesh, m, Vector3.ZERO)


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add_mesh(parent, b, m, pos)


func _add_mesh(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


func _mat(tex_path: String, c := Color(1, 1, 1)) -> StandardMaterial3D:
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
