class_name CamAudit
extends RefCounted
## Fixed cameras hide things. This measures how much, and picks the corner that hides least.
## A "feature" is anything the player has to find by looking: every doorway and every door slot of a room.
## For each place the player can stand in the room, the camera turns a little toward them (as in the game)
## and each feature is projected onto the 4:3 screen. Nothing here touches rules or sound.

const ASPECT := 4.0 / 3.0
const MARGIN := 0.9
const LEAF_TOP := 2.12

## every place a door leaf can stand, as [from, to] on the floor plan. a leaf is taller than the player
## and a camera right behind one sees nothing else, so a leaf between camera and target hides the target.
static var leaves: Array = []

static func leaf_blocks(cam: Vector3, p: Vector3, a: Vector2, b: Vector2) -> bool:
	var c := Vector2(cam.x, cam.z)
	var d := Vector2(p.x, p.z) - c
	var e := b - a
	var den := d.x * e.y - d.y * e.x
	if absf(den) < 0.0001:
		return false
	var w := a - c
	var t := (w.x * e.y - w.y * e.x) / den
	var u := (w.x * d.y - w.y * d.x) / den
	if t <= 0.02 or t >= 0.98 or u < 0.0 or u > 1.0:
		return false
	return lerpf(cam.y, p.y, t) < LEAF_TOP

## can p be seen from cam past every place a leaf might be? (a leaf standing at p itself does not count)
static func clear(cam: Vector3, p: Vector3) -> bool:
	for sg: Array in leaves:
		var mid: Vector2 = (sg[0] + sg[1]) * 0.5
		if mid.distance_to(Vector2(p.x, p.z)) < 0.95:
			continue
		if leaf_blocks(cam, p, sg[0], sg[1]):
			return false
	return true

## where a world point lands on the screen: x,y in -1..1 when visible, z > 0 when in front
static func project(pos: Vector3, look: Vector3, fov: float, p: Vector3) -> Vector3:
	var t := Transform3D(Basis.IDENTITY, pos).looking_at(look, Vector3.UP)
	var q := t.affine_inverse() * p
	if q.z > -0.15:
		return Vector3(9, 9, -1)
	var ty := tan(deg_to_rad(fov) * 0.5)
	return Vector3(q.x / (-q.z * ty * ASPECT), q.y / (-q.z * ty), -q.z)

static func on_screen(pos: Vector3, look: Vector3, fov: float, p: Vector3) -> bool:
	var s := project(pos, look, fov, p)
	return s.z > 0.0 and absf(s.x) < MARGIN and absf(s.y) < MARGIN

## [{at: Vector3, cell: Vector2i, key: Vector3i, kind: String}] for one set of cells
static func features(L: LevelLogic, B: Building, cells: Array) -> Array:
	var out := []
	var seen := {}
	for c: Vector2i in cells:
		for d in 4:
			var key := LevelLogic.edge_key(c, d)
			var t: int = L.edges.get(key, LevelLogic.Edge.WALL)
			if not L.cells.has(c + LevelLogic.DIRV[d]):
				continue
			if t != LevelLogic.Edge.OPEN and t != LevelLogic.Edge.ARCH and t != LevelLogic.Edge.SLOT:
				continue
			if t == LevelLogic.Edge.OPEN and (c + LevelLogic.DIRV[d]) in cells:
				continue   # the inside of the room is not something to find
			if seen.has(key):
				continue
			seen[key] = true
			out.append({"at": B.portal_center(key) + Vector3(0, 1.0, 0), "cell": c, "key": key, "kind": "door" if t == LevelLogic.Edge.SLOT else "way"})
	return out

## how much of what matters is on screen, 0..1, and which features are mostly hidden
static func score(cfg: Array, cells: Array, feats: Array) -> Dictionary:
	var got := 0.0
	var total := 0.0
	var seen_count := {}
	for c: Vector2i in cells:
		var stand := Building.cell_center(c)
		var look: Vector3 = (cfg[1] as Vector3).lerp(stand + Vector3(0, 1.0, 0), cfg[2])
		# the player themself, feet to hat
		total += 3.0
		if on_screen(cfg[0], look, cfg[3], stand + Vector3(0, 0.15, 0)) and on_screen(cfg[0], look, cfg[3], stand + Vector3(0, 1.75, 0)) and clear(cfg[0], stand + Vector3(0, 1.5, 0)):
			got += 3.0
		for i in feats.size():
			var f: Dictionary = feats[i]
			var w := 2.0 if f.cell == c else 1.0
			total += w
			if on_screen(cfg[0], look, cfg[3], f.at) and on_screen(cfg[0], look, cfg[3], f.at + Vector3(0, -0.8, 0)) and clear(cfg[0], f.at):
				got += w
				seen_count[i] = int(seen_count.get(i, 0)) + 1
	var hidden := []
	for i in feats.size():
		if float(seen_count.get(i, 0)) / maxf(1.0, cells.size()) < 0.5:
			hidden.append(feats[i])
	return {"score": got / maxf(total, 1.0), "hidden": hidden}

## the best fixed camera for a rectangular room. never looks south: "up" on screen is north, east or west.
static func best(L: LevelLogic, B: Building, cells: Array) -> Array:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c: Vector2i in cells:
		lo = lo.min(Vector2(c))
		hi = hi.max(Vector2(c) + Vector2.ONE)
	lo *= Building.CELL
	hi *= Building.CELL
	var cx := (lo.x + hi.x) * 0.5
	var cz := (lo.y + hi.y) * 0.5
	var feats := features(L, B, cells)
	var inset := 0.42
	var spots := [Vector3(hi.x - inset, 2.5, hi.y - inset), Vector3(lo.x + inset, 2.5, hi.y - inset), Vector3(cx, 2.5, hi.y - inset)]
	if hi.x - lo.x > hi.y - lo.y + 0.1:
		spots.append(Vector3(hi.x - inset, 2.5, cz))
		spots.append(Vector3(lo.x + inset, 2.5, cz))
	# last resort, with a price: the north side, looking south
	var north0 := spots.size()
	spots.append(Vector3(hi.x - inset, 2.5, lo.y + inset))
	spots.append(Vector3(lo.x + inset, 2.5, lo.y + inset))
	var best_cfg: Array = []
	var best_s := -1.0
	for si in spots.size():
		var pos: Vector3 = spots[si]
		if not (Building.world_to_cell(pos) in cells):
			continue
		for lx: float in [0.35, 0.5, 0.65]:
			for lz: float in [0.3, 0.45, 0.6]:
				var look := Vector3(lerpf(lo.x, hi.x, lx), 0.7, lerpf(lo.y, hi.y, lz))
				if Vector2(look.x - pos.x, look.z - pos.z).length() < 1.0:
					continue
				if si < north0 and look.z > pos.z - 0.2 and absf(look.x - pos.x) < 1.0:
					continue
				for fov: float in [60.0, 68.0, 76.0, 84.0]:
					for track: float in [0.2, 0.4]:
						var cfg := [pos, look, track, fov]
						var s: float = score(cfg, cells, feats).score - 0.004 * si - 0.0006 * (fov - 60.0) - (0.1 if si >= north0 else 0.0)
						if s > best_s:
							best_s = s
							best_cfg = cfg
	return best_cfg
