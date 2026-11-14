class_name SoundField
extends RefCounted
## How the bell travels through the building.
## Not physics: a portal graph. Sound walks from the telephone through every opening,
## pays for distance, pays a lot for a closed door leaf, a little for a grille or a vent.
## The listener hears the cheapest path, coming from the opening it arrives through.

const SIDE := 0.35
const COST_DOOR := 11.0
const COST_VENT := 5.0
const COST_GRILLE := 1.2
const COST_ARCH := 0.3
const COST_DUCT := 1.5

var L: LevelLogic
var B: Building
var doors: Array = []
var phone_pos := Vector3.ZERO
var phone_cell := Vector2i.ZERO

var n := 0
var pos: PackedVector3Array = []
var twin: PackedInt32Array = []
var key_of: Array[Vector3i] = []
var cell_nodes: Dictionary = {}
var node_cell: Array[Vector2i] = []
var dist: PackedFloat32Array = []
var muff: PackedFloat32Array = []
var pipe: PackedFloat32Array = []   # how many ducts the cheapest path came through
var duct_node: Dictionary = {}

func setup(logic: LevelLogic, building: Building, door_nodes: Array, phone: Vector3, ducts: Array = []) -> void:
	L = logic
	B = building
	doors = door_nodes
	phone_pos = phone
	phone_cell = Building.world_to_cell(phone)
	for key: Vector3i in L.edges:
		if L.edges[key] == LevelLogic.Edge.WALL:
			continue
		var ca := Vector2i(key.x, key.y)
		var cb := ca + (Vector2i(0, -1) if key.z == 1 else Vector2i(-1, 0))
		if not (L.cells.has(ca) and L.cells.has(cb)):
			continue
		var c := B.portal_center(key)
		var ia := _add(c, ca, key)
		var ib := _add(c, cb, key)
		twin[ia] = ib
		twin[ib] = ia
	# a duct joins two rooms for sound only. it is an extra opening, nothing else changes.
	for d: Array in ducts:
		var ia := _add_duct(d[0])
		var ib := _add_duct(d[1])
		twin[ia] = ib
		twin[ib] = ia
	n = pos.size()
	dist.resize(n)
	muff.resize(n)
	pipe.resize(n)

func _add(center: Vector3, cell: Vector2i, key: Vector3i) -> int:
	var to_cell := Building.cell_center(cell) - center
	to_cell.y = 0
	# push the node a little into its own cell, perpendicular to the edge
	var perp := Vector3(to_cell.x, 0, 0) if key.z == 0 else Vector3(0, 0, to_cell.z)
	pos.append(center + perp.normalized() * SIDE)
	twin.append(-1)
	key_of.append(key)
	node_cell.append(cell)
	if not cell_nodes.has(cell):
		cell_nodes[cell] = []
	cell_nodes[cell].append(pos.size() - 1)
	return pos.size() - 1

func _add_duct(p: Vector3) -> int:
	var cell := Building.world_to_cell(p)
	pos.append(Vector3(p.x, 0, p.z))
	twin.append(-1)
	key_of.append(Vector3i(-99, 0, 0))
	node_cell.append(cell)
	if not cell_nodes.has(cell):
		cell_nodes[cell] = []
	cell_nodes[cell].append(pos.size() - 1)
	duct_node[pos.size() - 1] = true
	return pos.size() - 1

func _cross(i: int) -> Vector2:
	if duct_node.has(i):
		return Vector2(COST_DUCT, 0.12)
	# x = cost in metres-equivalent, y = muffling
	var key := key_of[i]
	match L.edges[key]:
		LevelLogic.Edge.OPEN:
			return Vector2(SIDE * 2.0, 0.0)
		LevelLogic.Edge.ARCH:
			return Vector2(SIDE * 2.0 + COST_ARCH, 0.0)
		LevelLogic.Edge.GRILLE:
			return Vector2(SIDE * 2.0 + COST_GRILLE, 0.08)
		LevelLogic.Edge.VENT:
			return Vector2(SIDE * 2.0 + COST_VENT, 0.45)
		LevelLogic.Edge.SLOT:
			var o: Array = L.slot_owner[key]
			var cl: float = doors[o[0]].closedness(o[1])
			return Vector2(SIDE * 2.0 + COST_DOOR * cl, cl)
	return Vector2(999.0, 3.0)

func update() -> void:
	var done := PackedByteArray()
	done.resize(n)
	for i in n:
		dist[i] = 1e9
		muff[i] = 0.0
		pipe[i] = 0.0
	for i: int in cell_nodes.get(phone_cell, []):
		dist[i] = pos[i].distance_to(phone_pos)
	for _it in n:
		var u := -1
		var best := 1e9
		for i in n:
			if done[i] == 0 and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0:
			break
		done[u] = 1
		var tw := twin[u]
		var cr := _cross(u)
		if dist[u] + cr.x < dist[tw]:
			dist[tw] = dist[u] + cr.x
			muff[tw] = muff[u] + cr.y
			pipe[tw] = pipe[u] + (1.0 if duct_node.has(u) else 0.0)
		for v: int in cell_nodes[node_cell[u]]:
			if done[v] == 0:
				var nd := dist[u] + pos[u].distance_to(pos[v])
				if nd < dist[v]:
					dist[v] = nd
					muff[v] = muff[u]
					pipe[v] = pipe[u]

## returns {cost, muffle, from} for a listener position
func query(p: Vector3) -> Dictionary:
	var cell := Building.world_to_cell(p)
	var flat := Vector3(p.x, 0, p.z)
	var best := 1e9
	var bm := 0.0
	var bp := 0.0
	var from := phone_pos
	if cell == phone_cell:
		best = flat.distance_to(Vector3(phone_pos.x, 0, phone_pos.z))
	for i: int in cell_nodes.get(cell, []):
		var c := dist[i] + flat.distance_to(pos[i])
		if c < best:
			best = c
			bm = muff[i]
			bp = pipe[i]
			from = pos[i]
	return {"cost": best, "muffle": bm, "from": from, "pipe": bp}
