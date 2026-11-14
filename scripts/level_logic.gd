class_name LevelLogic
extends RefCounted
## Pure rules of the building: cells, edges, doors, the single knob.
## Shared by the game and by tools/solve.gd so that what is verified is what is played.

const E := 0
const N := 1
const W := 2
const S := 3
const DIRV: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1)]
const DIRNAME := ["E", "N", "W", "S"]

enum Edge { WALL, OPEN, ARCH, SLOT, GRILLE, VENT }

class DoorDef:
	var id: int
	var hinge: Vector2i
	var slots: Array[int] = []
	var ccw: bool = true
	var pos: int = 0

var cells: Dictionary = {}      # Vector2i -> String (room letter)
var edges: Dictionary = {}      # Vector3i(x, y, o) -> Edge ; o=0 edge west of cell, o=1 edge north of cell
var doors: Array[DoorDef] = []
var slot_owner: Dictionary = {} # edge key -> [door index, dir]
var phone_cell := Vector2i.ZERO
var start_cell := Vector2i.ZERO
var size := Vector2i.ZERO
var knob_on: int = -1           # -1 = in hand, else door index

static func edge_key(c: Vector2i, d: int) -> Vector3i:
	match d:
		E: return Vector3i(c.x + 1, c.y, 0)
		W: return Vector3i(c.x, c.y, 0)
		N: return Vector3i(c.x, c.y, 1)
	return Vector3i(c.x, c.y + 1, 1)

static func hinge_edge(h: Vector2i, d: int) -> Vector3i:
	match d:
		E: return Vector3i(h.x, h.y, 1)
		W: return Vector3i(h.x - 1, h.y, 1)
		N: return Vector3i(h.x, h.y - 1, 0)
	return Vector3i(h.x, h.y, 0)

## quadrant q around a hinge: 0=NE 1=NW 2=SW 3=SE
static func quadrant(h: Vector2i, q: int) -> Vector2i:
	match q & 3:
		0: return Vector2i(h.x, h.y - 1)
		1: return Vector2i(h.x - 1, h.y - 1)
		2: return Vector2i(h.x - 1, h.y)
	return Vector2i(h.x, h.y)

func load_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "cannot open level " + path)
	parse(f.get_as_text())

func parse(text: String) -> void:
	var lines := text.split("\n")
	var map_lines: Array[String] = []
	var in_map := false
	var hinges: Dictionary = {}
	var door_cfg: Dictionary = {}
	for raw in lines:
		var line: String = raw.rstrip("\r")
		if in_map:
			if line.strip_edges() == "end":
				in_map = false
			else:
				map_lines.append(line)
			continue
		var t := line.strip_edges()
		if t == "" or t.begins_with("#"):
			continue
		if t == "map":
			in_map = true
			continue
		var parts := t.split(" ", false)
		match parts[0]:
			"door":
				var cfg := {}
				for i in range(2, parts.size()):
					var kv := parts[i].split("=")
					cfg[kv[0]] = kv[1]
				door_cfg[int(parts[1])] = cfg
			"phone":
				phone_cell = Vector2i(int(parts[1]), int(parts[2]))
			"start":
				start_cell = Vector2i(int(parts[1]), int(parts[2]))
	var h := map_lines.size()
	for ly in range(h):
		var line := map_lines[ly]
		for lx in range(line.length()):
			var ch := line[lx]
			var cx := lx >> 1
			var cy := ly >> 1
			if ly % 2 == 1 and lx % 2 == 1:
				if ch != " " and ch != ".":
					cells[Vector2i(cx, cy)] = ch
					size.x = maxi(size.x, cx + 1)
					size.y = maxi(size.y, cy + 1)
			elif ly % 2 == 0 and lx % 2 == 0:
				if ch.is_valid_int():
					hinges[int(ch)] = Vector2i(cx, cy)
			else:
				var key := Vector3i(cx, cy, 1 if ly % 2 == 0 else 0)
				edges[key] = _edge_from_char(ch)
	# edges only matter next to existing cells; an edge with one side void is a wall
	for key: Vector3i in edges.keys():
		var a := Vector2i(key.x, key.y)
		var b := a + (Vector2i(0, -1) if key.z == 1 else Vector2i(-1, 0))
		if not (cells.has(a) and cells.has(b)):
			if cells.has(a) or cells.has(b):
				edges[key] = Edge.WALL
			else:
				edges.erase(key)
	var ids := hinges.keys()
	ids.sort()
	for id: int in ids:
		var d := DoorDef.new()
		d.id = id
		d.hinge = hinges[id]
		var cfg: Dictionary = door_cfg.get(id, {})
		var allowed: String = cfg.get("slots", "ENWS")
		for dir in range(4):
			var k := hinge_edge(d.hinge, dir)
			if edges.get(k, Edge.WALL) == Edge.SLOT and allowed.contains(DIRNAME[dir]):
				d.slots.append(dir)
				assert(not slot_owner.has(k), "slot shared by two hinges")
				slot_owner[k] = [doors.size(), dir]
		d.ccw = cfg.get("type", "ccw") == "ccw"
		d.pos = DIRNAME.find(cfg.get("start", DIRNAME[d.slots[0]]))
		assert(d.pos in d.slots, "door %d start not a slot" % id)
		doors.append(d)
	for k: Vector3i in edges.keys():
		if edges[k] == Edge.SLOT:
			assert(slot_owner.has(k), "door slot without hinge at %s" % str(k))

func _edge_from_char(ch: String) -> int:
	match ch:
		" ": return Edge.OPEN
		"D": return Edge.SLOT
		"A": return Edge.ARCH
		"g": return Edge.GRILLE
		"v": return Edge.VENT
	return Edge.WALL

func edge_type(c: Vector2i, d: int) -> int:
	return edges.get(edge_key(c, d), Edge.WALL)

func leaf_on_edge(key: Vector3i) -> bool:
	if not slot_owner.has(key):
		return false
	var o: Array = slot_owner[key]
	return doors[o[0]].pos == o[1]

func can_walk(c: Vector2i, d: int) -> bool:
	var n := c + DIRV[d]
	if not cells.has(n):
		return false
	var key := edge_key(c, d)
	match edges.get(key, Edge.WALL):
		Edge.OPEN, Edge.ARCH:
			return true
		Edge.SLOT:
			return not leaf_on_edge(key)
	return false

## the cell from which the door can be operated right now (the side that has the knob socket)
func op_cell(di: int, pos: int = -1) -> Vector2i:
	var d := doors[di]
	if pos < 0:
		pos = d.pos
	return quadrant(d.hinge, pos if d.ccw else pos + 3)

func blank_cell(di: int) -> Vector2i:
	var d := doors[di]
	return quadrant(d.hinge, d.pos + 3 if d.ccw else d.pos)

## possible rotation targets from the current position: array of [new_pos, turn(+1 ccw / -1 cw)]
func rotations(di: int) -> Array:
	var d := doors[di]
	var out := []
	for turn: int in [1, -1]:
		var np: int = (d.pos + turn + 4) & 3
		if np in d.slots and cells.has(op_cell(di, np)):
			out.append([np, turn])
	return out

## true if the rotation moves the leaf away from the operator (push), false if towards (pull)
func is_push(di: int, turn: int) -> bool:
	return (turn == -1) == doors[di].ccw

func state_key(cell: Vector2i) -> String:
	var s := "%d,%d|%d|" % [cell.x, cell.y, knob_on]
	for d in doors:
		s += str(d.pos)
	return s
