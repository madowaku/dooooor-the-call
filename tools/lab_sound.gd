extends SceneTree
## How much does one door change what is heard? Uses the game's own SoundField, untouched.
##   godot --headless --path . -s tools/lab_sound.gd -- --level=res://level/lab/a_fourway_alone.txt --door=1
## For every position of the chosen door: cost, muffling, and the resulting bell level / lowpass in every cell.

class FakeDoor:
	var def: LevelLogic.DoorDef
	func closedness(dir: int) -> float:
		return 1.0 if dir == def.pos else 0.0

func _init() -> void:
	var path := "res://level/lab/a_fourway_alone.txt"
	var door_id := 1
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			path = a.substr(8)
		elif a.begins_with("--door="):
			door_id = int(a.substr(7))
	var L := LevelLogic.new()
	L.load_file(path)
	var B := Building.new()
	B.L = L
	var doors := []
	var di := -1
	for i in L.doors.size():
		var f := FakeDoor.new()
		f.def = L.doors[i]
		doors.append(f)
		if L.doors[i].id == door_id:
			di = i
	var field := SoundField.new()
	var meta := LevelMeta.load_file(path)
	var ducts := []
	for d: Array in meta.ducts:
		ducts.append([Building.cell_center(d[0]) + Vector3(0, 0, -1.25), Building.cell_center(d[1]) + Vector3(0, 0, -1.25)])
	var src := Building.cell_center(L.phone_cell) + Vector3(0, 0.7, 0)
	if meta.source != Vector3.INF:
		src = meta.source
	field.setup(L, B, doors, src, ducts)
	var cells: Array = L.cells.keys()
	cells.sort()
	print("level %s, source in cell %s, turning door %d" % [path, L.phone_cell, door_id])
	var table := {}
	for pos: int in L.doors[di].slots:
		L.doors[di].pos = pos
		field.update()
		for c: Vector2i in cells:
			var q := field.query(Building.cell_center(c))
			var db := clampf(-0.72 * q.cost, -42.0, 0.0) - 2.0
			var cut := clampf(15000.0 * pow(0.26, q.muffle) / (1.0 + q.cost / 50.0), 380.0, 15000.0)
			var from: Vector3 = q.from - Building.cell_center(c)
			var dirn := "here"
			if Vector2(from.x, from.z).length() > 0.3:
				dirn = ("E" if from.x > 0 else "W") if absf(from.x) > absf(from.z) else ("S" if from.z > 0 else "N")
			if not table.has(c):
				table[c] = []
			table[c].append("%s: %5.1f dB %5.0f Hz %s%s" % [LevelLogic.DIRNAME[pos], db + meta.source_db, cut, dirn, " PIPE" if q.pipe > 0.5 else ""])
	for c: Vector2i in cells:
		print("  cell %s   %s" % [c, "   |   ".join(table[c])])
	B.free()
	quit(0)
