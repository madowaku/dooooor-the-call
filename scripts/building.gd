class_name Building
extends Node3D
## Builds the whole interior from the level plan: walls, floors, posts, lights, props, collisions.

const CELL := 3.0
const WALL_H := 2.8
const DOOR_H := 2.12
const TH := 0.1
const POST := 0.14
const SLOT_A := 0.14
const SLOT_B := 1.68
const ARCH_A := 0.65
const ARCH_B := 2.35
const ALL_LAYERS := 0xFFFFF

const ROOMS := {
	"s": {"wall": "wall_start", "floor": "floor_vinyl", "ceil": "ceil_panel", "step": "concrete"},
	"w": {"wall": "wall_green", "floor": "floor_lino", "ceil": "ceil_panel", "step": "concrete"},
	"n": {"wall": "wall_north", "floor": "floor_wood", "ceil": "ceil_wood", "step": "wood"},
	"e": {"wall": "wall_north", "floor": "floor_wood", "ceil": "ceil_wood", "step": "wood"},
	"c": {"wall": "wall_east", "floor": "floor_tile", "ceil": "ceil_panel", "step": "concrete"},
	"l": {"wall": "wall_lobby", "floor": "floor_carpet", "ceil": "ceil_panel", "step": "carpet"},
	"x": {"wall": "wall_concrete", "floor": "floor_concrete", "ceil": "ceil_wood", "step": "concrete"},
	"r": {"wall": "wall_tile", "floor": "floor_tile", "ceil": "ceil_panel", "step": "concrete"},
	"k": {"wall": "wall_wood", "floor": "floor_wood", "ceil": "ceil_wood", "step": "wood"},
	"p": {"wall": "wall_juraku", "floor": "floor_tatami", "ceil": "ceil_wood", "step": "carpet"},
}

const FLUO := Color(0.80, 0.95, 0.84)
const COLD := Color(0.78, 0.88, 1.0)
const BULB := Color(1.0, 0.74, 0.44)
const LAMP := Color(1.0, 0.64, 0.34)
## x, z, room, kind, color, energy, range
const LIGHTS := [
	[1.5, 16.4, "s", "tube", FLUO, 0.9, 5.5],
	[1.5, 13.0, "s", "tube", FLUO, 1.5, 5.0],
	[1.5, 10.2, "w", "tube", FLUO, 1.3, 5.5],
	[1.5, 5.2, "w", "tube", FLUO, 1.3, 5.5],
	[1.5, 1.5, "n", "bulb", BULB, 1.5, 5.5],
	[6.0, 1.5, "n", "bulb", BULB, 1.5, 5.5],
	[10.3, 1.5, "n", "bulb", BULB, 1.5, 5.5],
	[13.5, 1.5, "e", "bulb", BULB, 1.6, 5.0],
	[13.5, 4.9, "c", "tube", COLD, 1.4, 5.5],
	[13.5, 10.2, "c", "tube", COLD, 1.4, 5.5],
	[5.6, 10.5, "l", "bulb", BULB, 1.7, 6.5],
	[9.8, 10.6, "l", "bulb", BULB, 1.7, 6.5],
	[9.0, 13.6, "l", "bulb", BULB, 1.5, 6.0],
	[4.5, 13.5, "x", "bulb", BULB, 1.2, 4.5],
	[4.5, 4.5, "r", "tube", COLD, 1.6, 4.5],
	[10.5, 4.4, "k", "bulb", BULB, 0.75, 4.5],
	[7.5, 4.7, "p", "lamp", LAMP, 2.3, 6.0],
	[5.0, 7.5, "p", "bulb", LAMP, 1.2, 5.5],
	[10.4, 7.5, "p", "bulb", LAMP, 1.0, 5.0],
]

var L: LevelLogic
var room_bit: Dictionary = {}
var flicker_lights: Array = []
var bare := false          # test boards: walls, doors, one bulb per cell, the telephone. nothing else.
var phone_pos := Vector3.ZERO
var phone_handset: Node3D
var clock_pos := Vector3.ZERO
var vending_pos := Vector3.ZERO
var _mats: Dictionary = {}


class MB:
	var tools: Dictionary = {}

	func tool(m: String) -> SurfaceTool:
		if not tools.has(m):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[m] = st
		return tools[m]

	func quad(m: String, o: Vector3, du: Vector3, dv: Vector3, n: Vector3, uvo := Vector2.ZERO, uvdu := Vector2(1, 0), uvdv := Vector2(0, 1), step := 0.75) -> void:
		var st := tool(m)
		var nu := maxi(1, int(ceil(du.length() / step)))
		var nv := maxi(1, int(ceil(dv.length() / step)))
		var flip := du.cross(dv).dot(n) > 0.0
		for i in nu:
			for j in nv:
				var f0 := float(i) / nu
				var f1 := float(i + 1) / nu
				var g0 := float(j) / nv
				var g1 := float(j + 1) / nv
				var idx := [[f0, g0], [f1, g0], [f1, g1], [f0, g0], [f1, g1], [f0, g1]]
				if flip:
					idx = [[f0, g0], [f1, g1], [f1, g0], [f0, g0], [f0, g1], [f1, g1]]
				for fg: Array in idx:
					st.set_normal(n)
					st.set_uv(uvo + uvdu * fg[0] + uvdv * fg[1])
					st.add_vertex(o + du * fg[0] + dv * fg[1])

	func box(m: String, center: Vector3, size: Vector3, uvscale := 1.0) -> void:
		var h := size * 0.5
		var X := Vector3(size.x, 0, 0)
		var Y := Vector3(0, size.y, 0)
		var Z := Vector3(0, 0, size.z)
		var c := center - h
		var s := 0.5
		quad(m, c, X, Y, Vector3(0, 0, -1), Vector2.ZERO, Vector2(size.x * uvscale, 0), Vector2(0, -size.y * uvscale), s)
		quad(m, c + Z, X, Y, Vector3(0, 0, 1), Vector2.ZERO, Vector2(size.x * uvscale, 0), Vector2(0, -size.y * uvscale), s)
		quad(m, c, Z, Y, Vector3(-1, 0, 0), Vector2.ZERO, Vector2(size.z * uvscale, 0), Vector2(0, -size.y * uvscale), s)
		quad(m, c + X, Z, Y, Vector3(1, 0, 0), Vector2.ZERO, Vector2(size.z * uvscale, 0), Vector2(0, -size.y * uvscale), s)
		quad(m, c + Y, X, Z, Vector3(0, 1, 0), Vector2.ZERO, Vector2(size.x * uvscale, 0), Vector2(0, size.z * uvscale), s)
		quad(m, c, X, Z, Vector3(0, -1, 0), Vector2.ZERO, Vector2(size.x * uvscale, 0), Vector2(0, size.z * uvscale), s)

	func build(owner: Building) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for m: String in tools:
			var st: SurfaceTool = tools[m]
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, owner.mat(m))
		return mesh


static func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0, (c.y + 0.5) * CELL)

static func vertex_pos(v: Vector2i) -> Vector3:
	return Vector3(v.x * CELL, 0, v.y * CELL)

static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))

static func dir_vec(d: int) -> Vector3:
	var v := LevelLogic.DIRV[d]
	return Vector3(v.x, 0, v.y)


func mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if name.begins_with("#"):
		# "#rrggbb" flat colour, "#rrggbb!" unshaded/emissive
		var unlit := name.ends_with("!")
		m.albedo_color = Color.html(name.trim_suffix("!"))
		if unlit:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	elif name.begins_with("@"):
		# unshaded textured, alpha
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = load("res://assets/tex/%s.png" % name.substr(1))
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		m.albedo_texture = load("res://assets/tex/%s.png" % name)
		if name == "brass" or name == "iron":
			m.metallic_specular = 0.5
			m.roughness = 0.4
	_mats[name] = m
	return m


func edge_info(key: Vector3i) -> Dictionary:
	var t: int = L.edges.get(key, LevelLogic.Edge.WALL)
	var v0 := Vector2i(key.x, key.y)
	var v1 := v0 + (Vector2i(0, 1) if key.z == 0 else Vector2i(1, 0))
	if t == LevelLogic.Edge.SLOT:
		var hinge: Vector2i = L.doors[L.slot_owner[key][0]].hinge
		if hinge == v1:
			var tmp := v0
			v0 = v1
			v1 = tmp
	var p0 := vertex_pos(v0)
	return {"p0": p0, "a": (vertex_pos(v1) - p0).normalized(), "type": t}

func portal_center(key: Vector3i) -> Vector3:
	var info := edge_info(key)
	var s := CELL * 0.5
	if info.type == LevelLogic.Edge.SLOT:
		s = (SLOT_A + SLOT_B) * 0.5
	return info.p0 + info.a * s

func room_of(p: Vector3) -> String:
	return L.cells.get(world_to_cell(p), "")

func build(logic: LevelLogic) -> void:
	L = logic
	var bit := 0
	for r: String in ROOMS:
		room_bit[r] = 1 << bit
		bit += 1
	_build_cells()
	_build_edges()
	_build_posts()
	if bare:
		_build_bare()
	else:
		_build_lights()
		_build_props()


func _build_cells() -> void:
	var E := LevelLogic.Edge
	var up := Vector3.UP
	for c: Vector2i in L.cells:
		var room: String = L.cells[c]
		var style: Dictionary = ROOMS[room]
		var mb := MB.new()
		var o := vertex_pos(c)
		mb.quad(style.floor, o, Vector3(CELL, 0, 0), Vector3(0, 0, CELL), up, Vector2(c.x, c.y), Vector2(1, 0), Vector2(0, 1))
		mb.quad(style.ceil, o + up * WALL_H, Vector3(CELL, 0, 0), Vector3(0, 0, CELL), -up, Vector2(c.x, c.y), Vector2(1, 0), Vector2(0, 1))
		for d in 4:
			var key := LevelLogic.edge_key(c, d)
			var info := edge_info(key)
			var t: int = info.type
			if t == E.OPEN:
				continue
			var n_in := -dir_vec(d)
			var p0: Vector3 = info.p0
			var a: Vector3 = info.a
			var wm: String = style.wall
			var face := func(s0: float, s1: float, y0: float, y1: float) -> void:
				var u0 := (p0 + a * s0)
				var u1 := (p0 + a * s1)
				var uu0 := (u0.x + u0.z) / CELL
				var uu1 := (u1.x + u1.z) / CELL
				mb.quad(wm, p0 + a * s0 + n_in * TH + up * y0, a * (s1 - s0), up * (y1 - y0), n_in, Vector2(uu0, 1.0 - y0 / WALL_H), Vector2(uu1 - uu0, 0), Vector2(0, -(y1 - y0) / WALL_H))
			var cap := func(s0: float, s1: float) -> void:
				mb.quad("#0c0b0a!", p0 + a * s0 + up * WALL_H, a * (s1 - s0), n_in * TH, up)
			var jamb := func(s: float, sgn: float, y0: float, y1: float) -> void:
				mb.quad("wood_dark", p0 + a * s + up * y0, n_in * TH, up * (y1 - y0), a * sgn, Vector2.ZERO, Vector2(0.2, 0), Vector2(0, 1))
			var soffit := func(s0: float, s1: float, y: float, nrm: Vector3) -> void:
				mb.quad("wood_dark", p0 + a * s0 + up * y, a * (s1 - s0), n_in * TH, nrm, Vector2.ZERO, Vector2(1, 0), Vector2(0, 0.2))
			match t:
				E.WALL:
					face.call(0.0, CELL, 0.0, WALL_H)
					cap.call(0.0, CELL)
				E.SLOT:
					face.call(SLOT_B, CELL, 0.0, WALL_H)
					face.call(SLOT_A, SLOT_B, DOOR_H, WALL_H)
					jamb.call(SLOT_B, -1.0, 0.0, DOOR_H)
					soffit.call(SLOT_A, SLOT_B, DOOR_H, -up)
					cap.call(SLOT_B, CELL)
				E.ARCH:
					face.call(0.0, ARCH_A, 0.0, WALL_H)
					face.call(ARCH_B, CELL, 0.0, WALL_H)
					face.call(ARCH_A, ARCH_B, 2.25, WALL_H)
					jamb.call(ARCH_A, 1.0, 0.0, 2.25)
					jamb.call(ARCH_B, -1.0, 0.0, 2.25)
					soffit.call(ARCH_A, ARCH_B, 2.25, -up)
					cap.call(0.0, ARCH_A)
					cap.call(ARCH_B, CELL)
				E.GRILLE:
					face.call(0.0, 0.55, 0.0, WALL_H)
					face.call(2.45, CELL, 0.0, WALL_H)
					face.call(0.55, 2.45, 0.0, 0.9)
					face.call(0.55, 2.45, 1.95, WALL_H)
					jamb.call(0.55, 1.0, 0.9, 1.95)
					jamb.call(2.45, -1.0, 0.9, 1.95)
					soffit.call(0.55, 2.45, 1.95, -up)
					soffit.call(0.55, 2.45, 0.9, up)
					cap.call(0.0, 0.55)
					cap.call(2.45, CELL)
				E.VENT:
					face.call(0.0, CELL, 0.0, WALL_H)
					cap.call(0.0, CELL)
					mb.quad("iron", p0 + a * 1.1 + n_in * (TH + 0.012) + up * 2.12, a * 0.8, up * 0.36, n_in, Vector2.ZERO, Vector2(1, 0), Vector2(0, 6))
					for i in 5:
						mb.quad("#050505!", p0 + a * 1.14 + n_in * (TH + 0.02) + up * (2.15 + i * 0.066), a * 0.72, up * 0.03, n_in)
		var mi := MeshInstance3D.new()
		mi.mesh = mb.build(self)
		mi.layers = room_bit[room]
		mi.name = "cell_%d_%d" % [c.x, c.y]
		add_child(mi)


func _build_edges() -> void:
	var E := LevelLogic.Edge
	var body := StaticBody3D.new()
	body.name = "walls"
	add_child(body)
	var mb := MB.new()
	for key: Vector3i in L.edges:
		var info := edge_info(key)
		var t: int = info.type
		var spans := []
		match t:
			E.WALL, E.GRILLE, E.VENT:
				spans = [[0.0, CELL]]
			E.SLOT:
				spans = [[SLOT_B, CELL]]
			E.ARCH:
				spans = [[0.0, ARCH_A], [ARCH_B, CELL]]
		var a: Vector3 = info.a
		for sp: Array in spans:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			var along: float = sp[1] - sp[0]
			bs.size = Vector3(absf(a.x) * along + absf(a.z) * TH * 2.0, WALL_H, absf(a.z) * along + absf(a.x) * TH * 2.0)
			cs.shape = bs
			cs.position = info.p0 + a * (sp[0] + sp[1]) * 0.5 + Vector3(0, WALL_H * 0.5, 0)
			body.add_child(cs)
		if t == E.GRILLE:
			for i in 9:
				var s := 0.7 + i * 0.2
				mb.box("iron", info.p0 + a * s + Vector3(0, 1.425, 0), Vector3(0.04, 1.05, 0.04), 2.0)
			mb.box("iron", info.p0 + a * 1.5 + Vector3(0, 1.42, 0), Vector3(absf(a.x) * 1.9 + 0.03, 0.035, absf(a.z) * 1.9 + 0.03), 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build(self)
	mi.layers = ALL_LAYERS
	add_child(mi)


func _build_posts() -> void:
	var E := LevelLogic.Edge
	var hinges := {}
	for d in L.doors:
		hinges[d.hinge] = true
	var mb := MB.new()
	var body := StaticBody3D.new()
	add_child(body)
	for vy in range(L.size.y + 1):
		for vx in range(L.size.x + 1):
			var v := Vector2i(vx, vy)
			var any := false
			for d in 4:
				var k := LevelLogic.hinge_edge(v, d)
				if L.edges.has(k) and L.edges[k] != E.OPEN:
					any = true
			if not any:
				continue
			var p := vertex_pos(v)
			if hinges.has(v):
				continue   # the door builds its own round pivot post
			mb.box("wood_dark", p + Vector3(0, WALL_H * 0.5, 0), Vector3(POST * 2, WALL_H, POST * 2), 0.5)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(POST * 2, WALL_H, POST * 2)
			cs.shape = bs
			cs.position = p + Vector3(0, WALL_H * 0.5, 0)
			body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build(self)
	mi.layers = ALL_LAYERS
	add_child(mi)


func _build_lights() -> void:
	var mb := MB.new()
	for i in LIGHTS.size():
		var d: Array = LIGHTS[i]
		var pos := Vector3(d[0], 0, d[1])
		var l := OmniLight3D.new()
		l.light_color = d[4]
		l.light_energy = d[5]
		l.omni_range = d[6]
		l.omni_attenuation = 1.1
		l.shadow_enabled = false
		l.light_specular = 0.3
		l.light_cull_mask = room_bit[d[2]] | (1 << 19)
		l.set_meta("base", d[5])
		l.set_meta("room", d[2])
		match d[3]:
			"tube":
				l.position = pos + Vector3(0, WALL_H - 0.45, 0)
				mb.quad("#1c1c1a", pos + Vector3(-0.11, WALL_H - 0.07, -0.65), Vector3(0.22, 0, 0), Vector3(0, 0, 1.3), Vector3.DOWN)
				var tube := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.07, 0.05, 1.2)
				tube.mesh = bm
				var tm := StandardMaterial3D.new()
				tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				tm.albedo_color = Color(0.92, 1.0, 0.94) if d[4] != COLD else Color(0.9, 0.95, 1.0)
				tube.material_override = tm
				tube.position = pos + Vector3(0, WALL_H - 0.1, 0)
				add_child(tube)
				l.set_meta("tube", tube)
			"bulb":
				l.position = pos + Vector3(0, WALL_H - 0.6, 0)
				mb.box("#141210", pos + Vector3(0, WALL_H - 0.14, 0), Vector3(0.02, 0.28, 0.02))
				mb.box("#fff0c8!", pos + Vector3(0, WALL_H - 0.32, 0), Vector3(0.09, 0.11, 0.09))
			"lamp":
				l.position = pos + Vector3(0, 1.75, 0)
				mb.box("#141210", pos + Vector3(0, WALL_H - 0.4, 0), Vector3(0.02, 0.8, 0.02))
				mb.box("#c89a58!", pos + Vector3(0, 1.93, 0), Vector3(0.5, 0.2, 0.5))
				mb.box("#fff2d0!", pos + Vector3(0, 1.82, 0), Vector3(0.12, 0.1, 0.12))
		add_child(l)
		if i == 1:
			flicker_lights.append(l)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build(self)
	mi.layers = ALL_LAYERS
	add_child(mi)


func _build_bare() -> void:
	var mb := MB.new()
	for c: Vector2i in L.cells:
		var pos := cell_center(c)
		var l := OmniLight3D.new()
		l.light_color = BULB
		l.light_energy = 1.25
		l.omni_range = 5.0
		l.omni_attenuation = 1.1
		l.light_specular = 0.2
		l.position = pos + Vector3(0, WALL_H - 0.6, 0)
		l.light_cull_mask = room_bit[L.cells[c]] | (1 << 19)
		add_child(l)
		mb.box("#fff0c8!", pos + Vector3(0, WALL_H - 0.32, 0), Vector3(0.09, 0.11, 0.09))
	phone_pos = cell_center(L.phone_cell) + Vector3(0, 0, -0.9)
	mb.box("wood_mid", phone_pos + Vector3(0, 0.3, 0), Vector3(0.62, 0.6, 0.44), 1.0)
	mb.box("#e8e2d0", phone_pos + Vector3(0, 0.605, 0), Vector3(0.46, 0.012, 0.34))
	_solid(phone_pos + Vector3(0, 0.4, 0), Vector3(0.62, 0.8, 0.44))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build(self)
	mi.layers = ALL_LAYERS
	add_child(mi)
	_build_phone()


func _prop_mesh(mb: MB, room: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build(self)
	mi.layers = room_bit[room]
	add_child(mi)
	return mi

func _solid(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.position = center
	body.add_child(cs)
	add_child(body)

func _window(mb: MB, center: Vector3, along: Vector3, n_in: Vector3) -> void:
	# a night window: dark glass, pale frame. purely a wall decoration.
	var w := 1.5
	var h := 1.0
	var o := center - along * w * 0.5 + n_in * (TH + 0.015) - Vector3(0, h * 0.5, 0)
	mb.quad("#0a1420!", o, along * w, Vector3(0, h, 0), n_in)
	for f: float in [0.0, 0.5, 1.0]:
		mb.quad("wood_mid", o + along * (w * f - 0.03) + n_in * 0.01, along * 0.06, Vector3(0, h, 0), n_in)
	for f: float in [0.0, 1.0]:
		mb.quad("wood_mid", o + Vector3(0, h * f - 0.03, 0) + n_in * 0.01, along * w, Vector3(0, 0.06, 0), n_in)

func _sign(mb: MB, tex: String, center: Vector3, along: Vector3, n_in: Vector3, w := 0.62, h := 0.24) -> void:
	mb.quad("@" + tex, center - along * w * 0.5 - Vector3(0, h * 0.5, 0) + n_in * 0.02, along * w, Vector3(0, h, 0), n_in, Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), 9.0)


func _glow(pos: Vector3, room: String, c: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.light_specular = 0.0
	l.position = pos
	l.light_cull_mask = room_bit[room] | (1 << 19)
	add_child(l)

func _picture(mb: MB, center: Vector3, along: Vector3, n_in: Vector3, w: float, h: float, inner: String) -> void:
	var o := center - along * w * 0.5 - Vector3(0, h * 0.5, 0)
	mb.quad("wood_dark", o + n_in * 0.015, along * w, Vector3(0, h, 0), n_in)
	var m := 0.05
	mb.quad(inner, o + along * m + Vector3(0, m, 0) + n_in * 0.025, along * (w - m * 2), Vector3(0, h - m * 2, 0), n_in, Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), 9.0)

func _stain(mb: MB, center: Vector3, size: float, up: bool) -> void:
	var o := center - Vector3(size * 0.5, 0, size * 0.5)
	mb.quad("@stain", o, Vector3(size, 0, 0), Vector3(0, 0, size), Vector3.UP if up else Vector3.DOWN, Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), 9.0)


func _build_props() -> void:
	var X := Vector3(1, 0, 0)
	var Z := Vector3(0, 0, 1)
	# ---- start corridor: extinguisher, a window to nowhere
	var mb := MB.new()
	mb.box("#a02820", Vector3(0.24, 0.42, 13.6), Vector3(0.16, 0.5, 0.16))
	mb.box("#181818", Vector3(0.24, 0.72, 13.6), Vector3(0.06, 0.1, 0.06))
	_window(mb, Vector3(0, 1.55, 15.0), Z, X)
	# the green exit lamp: wherever you see it, you are back where you started
	mb.box("#143a26", Vector3(1.5, 2.44, 14.2), Vector3(0.74, 0.3, 0.07))
	mb.box("#141210", Vector3(1.24, 2.68, 14.2), Vector3(0.02, 0.24, 0.02))
	mb.box("#141210", Vector3(1.76, 2.68, 14.2), Vector3(0.02, 0.24, 0.02))
	_sign(mb, "sign_exit", Vector3(1.5, 2.44, 14.24), X, Z, 0.68, 0.25)
	_sign(mb, "sign_exit", Vector3(1.5, 2.44, 14.16), -X, -Z, 0.68, 0.25)
	_prop_mesh(mb, "s")
	_glow(Vector3(1.5, 2.2, 14.6), "s", Color(0.35, 1.0, 0.6), 0.55, 3.4)
	# ---- west corridor: windows, umbrella stand
	mb = MB.new()
	_window(mb, Vector3(0, 1.55, 10.5), Z, X)
	_window(mb, Vector3(0, 1.55, 7.5), Z, X)
	_window(mb, Vector3(0, 1.55, 4.5), Z, X)
	mb.box("iron", Vector3(2.62, 0.3, 8.2), Vector3(0.3, 0.6, 0.5), 2.0)
	mb.box("#20242c", Vector3(2.62, 0.75, 8.1), Vector3(0.04, 0.9, 0.04))
	_sign(mb, "sign_wash", Vector3(3.0 - TH, 2.3, 3.9), Z, -X)
	# the leak: a brown bloom on the ceiling, a dark pool, a bucket that nobody empties
	_stain(mb, Vector3(1.0, WALL_H - 0.012, 6.5), 1.9, false)
	_stain(mb, Vector3(1.0, 0.012, 6.5), 1.7, true)
	mb.box("#5a7a8c", Vector3(0.62, 0.15, 6.45), Vector3(0.28, 0.3, 0.28))
	mb.box("#0c1014!", Vector3(0.62, 0.302, 6.45), Vector3(0.22, 0.004, 0.22))
	# shoe shelf between the windows
	mb.box("wood_mid", Vector3(0.25, 0.5, 9.0), Vector3(0.26, 1.0, 1.34), 1.0)
	for sy in 3:
		for sz in 4:
			mb.quad("#120e0a!", Vector3(0.385, 0.1 + sy * 0.3, 8.4 + sz * 0.31), Z * 0.26, Vector3(0, 0.22, 0), X)
	mb.box("#d8d0b8", Vector3(0.36, 0.14, 8.86), Vector3(0.1, 0.07, 0.22))
	_picture(mb, Vector3(3.0 - TH, 1.5, 7.6), Z, -X, 0.5, 0.74, "poster")
	_prop_mesh(mb, "w")
	# ---- north corridor: windows facing north, a broom
	mb = MB.new()
	for wx: float in [1.5, 4.5, 7.5, 10.5]:
		_window(mb, Vector3(wx, 1.55, 0), X, Z)
	mb.box("wood_mid", Vector3(7.9, 0.75, 2.78), Vector3(0.035, 1.5, 0.035))
	mb.box("#8a7448", Vector3(7.9, 0.1, 2.76), Vector3(0.3, 0.2, 0.06))
	# fire alarm: a white panel and a red lamp that is always on
	mb.box("#d4cfc0", Vector3(5.6, 1.35, 3.0 - TH - 0.04), Vector3(0.42, 0.56, 0.08))
	mb.box("#b02a22", Vector3(5.6, 1.4, 3.0 - TH - 0.09), Vector3(0.16, 0.16, 0.04))
	mb.box("#ff4a30!", Vector3(5.6, 2.02, 3.0 - TH - 0.07), Vector3(0.13, 0.13, 0.13))
	_picture(mb, Vector3(9.2, 1.55, 3.0 - TH), -X, -Z, 0.42, 0.62, "calendar")
	_prop_mesh(mb, "n")
	_glow(Vector3(5.6, 1.9, 2.5), "n", Color(1.0, 0.25, 0.15), 0.9, 3.6)
	mb = MB.new()
	_window(mb, Vector3(13.5, 1.55, 0), X, Z)
	_window(mb, Vector3(15.0, 1.55, 1.5), Z, -X)
	# bottle crates stacked in the corner
	mb.box("#2c4c8c", Vector3(14.58, 0.15, 2.6), Vector3(0.5, 0.3, 0.36))
	mb.box("#2c4c8c", Vector3(14.6, 0.45, 2.62), Vector3(0.5, 0.3, 0.36))
	mb.box("#c8a030", Vector3(14.57, 0.75, 2.6), Vector3(0.5, 0.3, 0.36))
	mb.box("#2c4c8c", Vector3(14.0, 0.15, 2.66), Vector3(0.5, 0.3, 0.36))
	_prop_mesh(mb, "e")
	# ---- east corridor: hose box, windows
	mb = MB.new()
	_window(mb, Vector3(15.0, 1.55, 7.5), Z, -X)
	_window(mb, Vector3(15.0, 1.55, 10.5), Z, -X)
	mb.box("#9a2a22", Vector3(14.78, 1.1, 4.6), Vector3(0.22, 0.7, 0.5))
	# three small framed pictures in a row on the inner wall
	_picture(mb, Vector3(12.0 + TH, 1.6, 6.7), -Z, X, 0.5, 0.4, "#7a8a5a")
	_picture(mb, Vector3(12.0 + TH, 1.6, 7.5), -Z, X, 0.5, 0.4, "#9a6a48")
	_picture(mb, Vector3(12.0 + TH, 1.6, 8.3), -Z, X, 0.5, 0.4, "#4a5e80")
	_prop_mesh(mb, "c")
	# ---- lobby: bench, vending machine, notice board, clock, plant
	mb = MB.new()
	mb.box("wood_mid", Vector3(7.4, 0.42, 14.62), Vector3(1.7, 0.08, 0.5), 1.0)
	mb.box("wood_dark", Vector3(6.7, 0.2, 14.62), Vector3(0.08, 0.4, 0.44))
	mb.box("wood_dark", Vector3(8.1, 0.2, 14.62), Vector3(0.08, 0.4, 0.44))
	_solid(Vector3(7.4, 0.3, 14.62), Vector3(1.7, 0.6, 0.5))
	vending_pos = Vector3(10.9, 0.95, 14.48)
	mb.box("#b43c30", vending_pos, Vector3(1.0, 1.9, 0.72))
	_solid(vending_pos, Vector3(1.0, 1.9, 0.72))
	mb.box("#3a2a1c", Vector3(3.5, 0.25, 9.5), Vector3(0.4, 0.5, 0.4))
	mb.box("#2a5a34", Vector3(3.5, 0.85, 9.5), Vector3(0.5, 0.7, 0.5))
	mb.box("#347040", Vector3(3.5, 1.3, 9.5), Vector3(0.28, 0.4, 0.28))
	_solid(Vector3(3.5, 0.6, 9.5), Vector3(0.45, 1.2, 0.45))
	mb.quad("board", Vector3(6.6, 1.2, 9.0 + TH + 0.06), X * 1.2, Vector3(0, 0.9, 0), Z, Vector2(0, 1), Vector2(1, 0), Vector2(0, -1))
	mb.box("wood_dark", Vector3(7.2, 1.65, 9.0 + TH + 0.02), Vector3(1.3, 1.0, 0.03))
	_sign(mb, "sign_lobby", Vector3(10.5, 2.42, 9.0 + TH), X, Z)
	_sign(mb, "sign_store", Vector3(4.0, 2.42, 12.0 - TH), -X, -Z)
	clock_pos = Vector3(9.2, 2.15, 9.0 + TH + 0.03)
	mb.quad("@clock", clock_pos + Vector3(-0.22, -0.22, 0), X * 0.44, Vector3(0, 0.44, 0), Z, Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), 9.0)
	_prop_mesh(mb, "l")
	var vf := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.94, 1.84)
	vf.mesh = qm
	var vm := StandardMaterial3D.new()
	vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vm.albedo_texture = load("res://assets/tex/vending.png")
	vf.material_override = vm
	vf.position = vending_pos + Vector3(0, 0, -0.365)
	vf.rotation.y = PI
	add_child(vf)
	var vl := OmniLight3D.new()
	vl.light_color = Color(0.9, 0.95, 1.0)
	vl.light_energy = 0.9
	vl.omni_range = 3.2
	vl.position = vending_pos + Vector3(0, 0.2, -0.9)
	vl.light_cull_mask = room_bit["l"] | (1 << 19)
	add_child(vl)
	# ---- closet: boxes and a bucket
	mb = MB.new()
	mb.box("#7a6a4a", Vector3(5.4, 0.3, 14.4), Vector3(0.7, 0.6, 0.7))
	mb.box("#6a5c42", Vector3(5.45, 0.85, 14.45), Vector3(0.55, 0.5, 0.55))
	mb.box("#5a646e", Vector3(3.6, 0.18, 14.5), Vector3(0.36, 0.36, 0.36))
	mb.box("wood_mid", Vector3(3.62, 0.7, 14.72), Vector3(0.03, 1.4, 0.03))
	_solid(Vector3(5.4, 0.5, 14.4), Vector3(0.7, 1.0, 0.7))
	_prop_mesh(mb, "x")
	# ---- washroom: basin, mirror, pipe
	mb = MB.new()
	mb.box("#d8dcd4", Vector3(4.5, 0.78, 5.66), Vector3(1.3, 0.16, 0.5))
	mb.box("#b8beb6", Vector3(4.5, 0.38, 5.74), Vector3(0.14, 0.76, 0.14))
	mb.box("iron", Vector3(4.5, 0.98, 5.82), Vector3(0.04, 0.22, 0.04))
	mb.quad("#5a7078!", Vector3(5.0, 1.15, 6.0 - TH - 0.04), -X * 1.0, Vector3(0, 0.7, 0), -Z)
	mb.box("wood_mid", Vector3(4.5, 1.5, 6.0 - TH - 0.01), Vector3(1.08, 0.78, 0.02))
	_solid(Vector3(4.5, 0.45, 5.66), Vector3(1.3, 0.9, 0.5))
	_prop_mesh(mb, "r")
	# ---- nook: plate above the phone room doorway, a stool
	mb = MB.new()
	_sign(mb, "sign_phone", Vector3(11.1, 2.42, 6.0 - TH), -X, -Z)
	mb.box("wood_mid", Vector3(9.6, 0.42, 3.55), Vector3(0.34, 0.05, 0.34))
	mb.box("wood_dark", Vector3(9.6, 0.2, 3.55), Vector3(0.22, 0.4, 0.22))
	_prop_mesh(mb, "k")
	# ---- phone room: the stand, the doily, a cushion, a low table
	phone_pos = Vector3(7.5, 0.0, 3.62)
	mb = MB.new()
	mb.box("wood_mid", phone_pos + Vector3(0, 0.3, 0), Vector3(0.62, 0.6, 0.44), 1.0)
	mb.box("#e8e2d0", phone_pos + Vector3(0, 0.605, 0), Vector3(0.46, 0.012, 0.34))
	_solid(phone_pos + Vector3(0, 0.4, 0), Vector3(0.62, 0.8, 0.44))
	mb.box("#5a2a3a", Vector3(7.5, 0.05, 4.75), Vector3(0.6, 0.1, 0.6))
	mb.box("wood_dark", Vector3(4.1, 0.28, 8.3), Vector3(1.1, 0.06, 0.8), 1.0)
	mb.box("wood_dark", Vector3(4.1, 0.13, 8.3), Vector3(0.9, 0.26, 0.6), 1.0)
	_solid(Vector3(4.1, 0.2, 8.3), Vector3(1.1, 0.4, 0.8))
	mb.box("#6a3a2a", Vector3(10.6, 0.05, 7.6), Vector3(0.6, 0.1, 0.6))
	# hanging scroll on the north wall of the long part
	mb.quad("#d8ceb0", Vector3(4.2, 0.9, 6.0 + TH + 0.02), X * 0.5, Vector3(0, 1.4, 0), Z)
	mb.quad("#2a2622", Vector3(4.33, 1.25, 6.0 + TH + 0.03), X * 0.24, Vector3(0, 0.7, 0), Z)
	_prop_mesh(mb, "p")
	_build_phone()


func _build_phone() -> void:
	var root := Node3D.new()
	root.name = "phone"
	root.position = phone_pos + Vector3(0, 0.612, 0)
	add_child(root)
	var phone_layers: int = room_bit[L.cells.get(L.phone_cell, "p")]
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	black.albedo_color = Color(0.035, 0.035, 0.04)
	black.roughness = 0.25
	black.metallic_specular = 0.9
	var parts := [
		[Vector3(0.24, 0.07, 0.2), Vector3(0, 0.035, 0)],
		[Vector3(0.2, 0.05, 0.15), Vector3(0, 0.09, -0.015)],
		[Vector3(0.05, 0.05, 0.06), Vector3(-0.075, 0.135, -0.03)],
		[Vector3(0.05, 0.05, 0.06), Vector3(0.075, 0.135, -0.03)],
	]
	for p: Array in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.material_override = black
		mi.position = p[1]
		mi.layers = phone_layers
		root.add_child(mi)
	var dial := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.11, 0.11)
	dial.mesh = qm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	dm.albedo_texture = load("res://assets/tex/dial.png")
	dial.material_override = dm
	dial.position = Vector3(0, 0.098, 0.062)
	dial.rotation.x = -1.05
	dial.layers = phone_layers
	root.add_child(dial)
	phone_handset = make_handset(black)
	phone_handset.position = Vector3(0, 0.172, -0.03)
	root.add_child(phone_handset)

func make_handset(black: Material = null) -> Node3D:
	if black == null:
		var b := StandardMaterial3D.new()
		b.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		b.albedo_color = Color(0.035, 0.035, 0.04)
		b.roughness = 0.25
		b.metallic_specular = 0.9
		black = b
	var n := Node3D.new()
	var parts := [
		[Vector3(0.2, 0.03, 0.04), Vector3(0, 0, 0)],
		[Vector3(0.06, 0.05, 0.06), Vector3(-0.095, -0.012, 0)],
		[Vector3(0.06, 0.05, 0.06), Vector3(0.095, -0.012, 0)],
	]
	for p: Array in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.material_override = black
		mi.position = p[1]
		mi.layers = ALL_LAYERS
		n.add_child(mi)
	return n


## exterior set for the title shot, built far away from the interior
func build_exterior(origin: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = origin
	add_child(root)
	var mb := MB.new()
	mb.quad("asphalt", Vector3(-30, 0, -6), Vector3(60, 0, 0), Vector3(0, 0, 40), Vector3.UP, Vector2.ZERO, Vector2(20, 0), Vector2(0, 14), 4.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build(self)
	mi.layers = 1 << 18
	root.add_child(mi)
	var fac := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(22, 17)
	qm.subdivide_width = 12
	qm.subdivide_depth = 10
	fac.mesh = qm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	fm.albedo_texture = load("res://assets/tex/facade.png")
	fm.emission_enabled = true
	fm.emission_texture = load("res://assets/tex/facade_emit.png")
	fm.emission_energy_multiplier = 1.6
	fm.roughness = 1.0
	fm.metallic_specular = 0.0
	fm.uv1_scale = Vector3(1, 1, 1)
	fac.material_override = fm
	fac.position = Vector3(0, 8.5, -6)
	fac.layers = 1 << 18
	root.add_child(fac)
	var door := MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(1.7, 2.3)
	door.mesh = dq
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	em.albedo_texture = load("res://assets/tex/entrance.png")
	door.material_override = em
	door.position = Vector3(0, 1.15, -5.97)
	door.layers = 1 << 18
	root.add_child(door)
	var canopy := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(3.0, 0.16, 1.4)
	canopy.mesh = cb
	canopy.material_override = mat("#4a4844")
	canopy.position = Vector3(0, 2.6, -5.3)
	canopy.layers = 1 << 18
	root.add_child(canopy)
	var pole := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.12, 5.0, 0.12)
	pole.mesh = pb
	pole.material_override = mat("#2a2c2a")
	pole.position = Vector3(7.2, 2.5, -1.0)
	pole.layers = 1 << 18
	root.add_child(pole)
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.7, 0.1, 0.22)
	head.mesh = hb
	head.material_override = mat("#e8fff0!")
	head.position = Vector3(6.9, 5.0, -1.0)
	root.add_child(head)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.7, 0.95, 0.82)
	lamp.light_energy = 2.6
	lamp.omni_range = 13.0
	lamp.position = Vector3(5.6, 4.6, -0.2)
	lamp.light_cull_mask = (1 << 18) | (1 << 19)
	root.add_child(lamp)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.7, 0.4)
	glow.light_energy = 1.2
	glow.omni_range = 7.0
	glow.position = Vector3(0, 2.2, -4.6)
	glow.light_cull_mask = (1 << 18) | (1 << 19)
	root.add_child(glow)
	return root
