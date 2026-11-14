extends SceneTree
## Exhaustive search of the building's state space (solvability, dead ends, shortcuts).
## run: godot --headless --path . -s tools/solve.gd

func _init() -> void:
	var L := LevelLogic.new()
	L.load_file("res://level/building.txt")
	print("cells=%d doors=%d" % [L.cells.size(), L.doors.size()])
	for i in L.doors.size():
		var d := L.doors[i]
		var sl := []
		for s in d.slots:
			sl.append(LevelLogic.DIRNAME[s])
		print("  door %d hinge=%s slots=%s socket=%s start=%s operable-from=%s" % [d.id, d.hinge, sl, "ccw" if d.ccw else "cw", LevelLogic.DIRNAME[d.pos], L.op_cell(i)])
	var res := Solver.search(L, L.start_cell)
	print("reachable states: %d" % res.count)
	print("goal reachable: %s   minimum door turns: %d" % [res.found, res.rot])
	print("dead-end states (goal unreachable from them): %d" % res.dead)
	print("cells never reachable: %s" % [res.unvisited])
	print("one shortest solution:")
	for line in Solver.describe(L, res.actions):
		print("   " + line)
	print("necessity of each door (is the phone reachable if the door is never turned?):")
	for i in L.doors.size():
		var r := Solver.search(L, L.start_cell, [i])
		print("   never turn door %d: %s (turns=%d)" % [L.doors[i].id, r.found, r.rot])
	for i in L.doors.size():
		for j in range(i + 1, L.doors.size()):
			var r := Solver.search(L, L.start_cell, [i, j])
			print("   never turn doors %d,%d: %s (turns=%d)" % [L.doors[i].id, L.doors[j].id, r.found, r.rot])
	var ok: bool = res.found and res.dead == 0 and res.unvisited.is_empty() and res.rot >= 5
	print("VERDICT: %s" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)
