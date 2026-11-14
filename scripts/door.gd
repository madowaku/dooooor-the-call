class_name Door
extends Node3D
## One knobless door: a heavy leaf turning around a round post.
## The leaf always plugs exactly one doorway. Only one face has a socket for the knob.

signal turn_finished

const LEAF_A := 0.16
const LEAF_B := 1.64
const LEAF_H := 2.07
const LEAF_T := 0.07
const KNOB_X := 1.345
const KNOB_Y := 1.03
const RIDER_X := 1.18
const RIDER_Z := 0.62

var index := 0
var def: LevelLogic.DoorDef
var B: Building
var pivot: Node3D
var knob: Node3D
var side := 1.0            # +1: socket on local +z face, -1: on local -z face
var turning := false
var anim_from := -1
var anim_to := -1
var anim_t := 0.0
var _groan := 0.0

func setup(i: int, d: LevelLogic.DoorDef, building: Building) -> void:
	index = i
	def = d
	B = building
	side = -1.0 if d.ccw else 1.0
	position = Building.vertex_pos(d.hinge)
	var layers := 0
	for q in 4:
		var c := LevelLogic.quadrant(d.hinge, q)
		if B.L.cells.has(c):
			layers |= B.room_bit[B.L.cells[c]]
	# round pivot post with brass collars
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = Building.WALL_H
	cyl.radial_segments = 8
	cyl.rings = 4
	post.mesh = cyl
	post.material_override = B.mat("wood_dark")
	post.position.y = Building.WALL_H * 0.5
	post.layers = Building.ALL_LAYERS
	add_child(post)
	for y: float in [0.12, LEAF_H + 0.02]:
		var ring := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		rc.top_radius = 0.175
		rc.bottom_radius = 0.175
		rc.height = 0.07
		rc.radial_segments = 8
		ring.mesh = rc
		ring.material_override = B.mat("brass")
		ring.position.y = y
		ring.layers = Building.ALL_LAYERS
		add_child(ring)
	var body := StaticBody3D.new()
	var pc := CollisionShape3D.new()
	var ps := CylinderShape3D.new()
	ps.radius = 0.16
	ps.height = Building.WALL_H
	pc.shape = ps
	pc.position.y = Building.WALL_H * 0.5
	body.add_child(pc)
	add_child(body)

	pivot = Node3D.new()
	add_child(pivot)
	pivot.rotation.y = d.pos * PI * 0.5
	var mb := Building.MB.new()
	var w := LEAF_B - LEAF_A
	var X := Vector3(w, 0, 0)
	var Y := Vector3(0, LEAF_H, 0)
	var o := Vector3(LEAF_A, 0.02, 0)
	var front := "door_socket" if side > 0 else "door_blank"
	var back := "door_blank" if side > 0 else "door_socket"
	mb.quad(front, o + Vector3(0, 0, LEAF_T * 0.5), X, Y, Vector3(0, 0, 1), Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), 0.5)
	mb.quad(back, o - Vector3(0, 0, LEAF_T * 0.5), X, Y, Vector3(0, 0, -1), Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), 0.5)
	var Zt := Vector3(0, 0, LEAF_T)
	mb.quad("wood_mid", o + X - Zt * 0.5, Zt, Y, Vector3(1, 0, 0), Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 1), 0.5)
	mb.quad("wood_mid", o - Zt * 0.5, Zt, Y, Vector3(-1, 0, 0), Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 1), 0.5)
	mb.quad("wood_mid", o + Y - Zt * 0.5, X, Zt, Vector3(0, 1, 0), Vector2.ZERO, Vector2(1, 0), Vector2(0, 0.1), 0.5)
	# brass strap hinges hugging the post
	for y: float in [0.35, 1.75]:
		mb.box("brass", Vector3(LEAF_A + 0.16, y, 0), Vector3(0.36, 0.06, LEAF_T + 0.02), 3.0)
	var leaf := MeshInstance3D.new()
	leaf.mesh = mb.build(B)
	leaf.layers = layers
	pivot.add_child(leaf)
	var lb := StaticBody3D.new()
	var lc := CollisionShape3D.new()
	var ls := BoxShape3D.new()
	ls.size = Vector3(w, LEAF_H, 0.12)
	lc.shape = ls
	lc.position = Vector3((LEAF_A + LEAF_B) * 0.5, LEAF_H * 0.5, 0)
	lb.add_child(lc)
	pivot.add_child(lb)

	knob = Node3D.new()
	knob.position = Vector3(KNOB_X, KNOB_Y, side * LEAF_T * 0.5)
	knob.rotation.y = 0.0 if side > 0 else PI
	knob.add_child(make_knob(B))
	knob.visible = false
	pivot.add_child(knob)

## a brass knob pointing along +z, base at the origin
static func make_knob(building: Building) -> Node3D:
	var n := Node3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.albedo_color = Color(0.86, 0.66, 0.26)
	m.roughness = 0.3
	m.metallic_specular = 0.9
	m.emission_enabled = true
	m.emission = Color(0.35, 0.24, 0.06)
	var stem := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.016
	sc.bottom_radius = 0.022
	sc.height = 0.06
	sc.radial_segments = 6
	stem.mesh = sc
	stem.rotation.x = PI * 0.5
	stem.position.z = 0.03
	stem.material_override = m
	stem.layers = Building.ALL_LAYERS
	n.add_child(stem)
	var rose := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.036
	rc.bottom_radius = 0.036
	rc.height = 0.012
	rc.radial_segments = 8
	rose.mesh = rc
	rose.rotation.x = PI * 0.5
	rose.position.z = 0.006
	rose.material_override = m
	rose.layers = Building.ALL_LAYERS
	n.add_child(rose)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.042
	sm.height = 0.066
	sm.radial_segments = 7
	sm.rings = 4
	ball.mesh = sm
	ball.rotation.x = PI * 0.5
	ball.position.z = 0.078
	ball.material_override = m
	ball.layers = Building.ALL_LAYERS
	n.add_child(ball)
	return n

func set_knob(on: bool) -> void:
	knob.visible = on

func hole_world() -> Vector3:
	return pivot.to_global(Vector3(KNOB_X, KNOB_Y, side * LEAF_T * 0.5))

## outward normal of the socket face, in world space
func socket_normal() -> Vector3:
	return (pivot.global_transform.basis * Vector3(0, 0, side)).normalized()

func rider_local(socket_side := true) -> Vector3:
	return Vector3(RIDER_X, 0, (side if socket_side else -side) * RIDER_Z)

func rider_world(socket_side := true) -> Vector3:
	var p := pivot.to_global(rider_local(socket_side))
	p.y = 0
	return p

## where the operator would stand if the leaf were in slot `pos`
func rider_world_at(pos: int) -> Vector3:
	var b := Basis(Vector3.UP, pos * PI * 0.5)
	return global_position + b * rider_local(true)

func rider_yaw(socket_side := true) -> float:
	var s := side if socket_side else -side
	return pivot.global_rotation.y + (0.0 if s > 0 else PI)

func closedness(dir: int) -> float:
	if turning:
		if dir == anim_from:
			return clampf(1.0 - anim_t * 2.5, 0.0, 1.0)
		if dir == anim_to:
			return clampf((anim_t - 0.75) * 4.0, 0.0, 1.0)
		return 0.0
	return 1.0 if dir == def.pos else 0.0

func turn(new_pos: int, dir_sign: int, dur: float) -> void:
	turning = true
	anim_from = def.pos
	anim_to = new_pos
	anim_t = 0.0
	var a0 := pivot.rotation.y
	var a1 := a0 + dir_sign * PI * 0.5
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		anim_t = t
		# heavy start, long push, a hard stop against the frame with a tiny rebound
		var e := t * t * (3.0 - 2.0 * t)
		var bump := 0.0
		if t > 0.9:
			bump = sin((t - 0.9) * 10.0 * PI) * 0.012 * (1.0 - t) * 10.0
		pivot.rotation.y = lerpf(a0, a1, e) - dir_sign * bump
	, 0.0, 1.0, dur)
	await tw.finished
	pivot.rotation.y = new_pos * PI * 0.5
	def.pos = new_pos
	turning = false
	anim_t = 0.0
	turn_finished.emit()
