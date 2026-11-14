extends SceneTree
## Puzzle laboratory: small experiment boards, measured with counterfactual searches.
## It never touches the game's own rules (LevelLogic) or solver; it only asks them questions.
##
##   godot --headless --path . -s tools/lab.gd                 evaluate every level/lab/*.txt
##   godot --headless --path . -s tools/lab.gd -- --gen=4000   random small boards, print the most interesting
##
## What "the trick is the centre of the solution" means here:
##   frozen  : the board cannot be solved if that door is never turned
##   no_pull : ... if the player may never pull a door shut behind them (only push and follow)
##   no_push : ... if the player may never push and follow
##   no_take : ... if the knob may never be taken out again once it is in a door

func _init() -> void:
	var gen := 0
	var w := 4
	var h := 3
	var nd := 2
	var sd := 1
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--gen="):
			gen = int(a.substr(6))
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			w = int(p[0])
			h = int(p[1])
		elif a.begins_with("--doors="):
			nd = int(a.substr(8))
		elif a.begins_with("--seed="):
			sd = int(a.substr(7))
	if gen > 0:
		_generate(gen, w, h, nd, sd)
	else:
		_evaluate_dir("res://level/lab")
	quit(0)


# ------------------------------------------------------------------ search with switches
static func _snap(L: LevelLogic) -> Array:
	var p := []
	for d in L.doors:
		p.append(d.pos)
	return [p, L.knob_on]

static func _restore(L: LevelLogic, s: Array) -> void:
	for i in L.doors.size():
		L.doors[i].pos = s[0][i]
	L.knob_on = s[1]

static func search(L: LevelLogic, opt: Dictionary = {}) -> Dictionary:
	var frozen: Array = opt.get("frozen", [])
	var init := _snap(L)
	var sk := L.state_key(L.start_cell)
	var info := {sk: {"cell": L.start_cell, "snap": init, "rot": 0, "prev": "", "act": {"t": "start"}}}
	var dq: Array = [sk]
	var goal := ""
	while not dq.is_empty():
		var key: String = dq.pop_front()
		var st: Dictionary = info[key]
		_restore(L, st.snap)
		var cell: Vector2i = st.cell
		if cell == L.phone_cell:
			goal = key
			break
		var nexts := []
		for d in 4:
			if L.can_walk(cell, d):
				nexts.append([cell + LevelLogic.DIRV[d], _snap(L), 0, {"t": "walk", "to": cell + LevelLogic.DIRV[d]}])
		for di in L.doors.size():
			if di in frozen or L.op_cell(di) != cell:
				continue
			if L.knob_on == -1:
				L.knob_on = di
				nexts.append([cell, _snap(L), 0, {"t": "attach", "door": di}])
				L.knob_on = -1
			elif L.knob_on == di:
				if not opt.get("no_take", false):
					L.knob_on = -1
					nexts.append([cell, _snap(L), 0, {"t": "detach", "door": di}])
					L.knob_on = di
				for r: Array in L.rotations(di):
					var push := L.is_push(di, r[1])
					if (push and opt.get("no_push", false)) or (not push and opt.get("no_pull", false)):
						continue
					var old := L.doors[di].pos
					L.doors[di].pos = r[0]
					var nc := L.op_cell(di)
					nexts.append([nc, _snap(L), 1, {"t": "turn", "door": di, "from": old, "pos": r[0], "turn": r[1], "push": push, "to": nc}])
					L.doors[di].pos = old
		for nx: Array in nexts:
			_restore(L, nx[1])
			var nk := L.state_key(nx[0])
			var nr: int = st.rot + nx[2]
			if not info.has(nk) or info[nk].rot > nr:
				info[nk] = {"cell": nx[0], "snap": nx[1], "rot": nr, "prev": key, "act": nx[3]}
				if nx[2] == 0:
					dq.push_front(nk)
				else:
					dq.push_back(nk)
	var actions := []
	var k := goal
	while k != "" and info.has(k):
		actions.push_front(info[k].act)
		k = info[k].prev
	_restore(L, init)
	return {"found": goal != "", "rot": info[goal].rot if goal != "" else -1, "actions": actions, "seen": info.size()}


static func measure(L: LevelLogic) -> Dictionary:
	var base := search(L)
	var m := {"found": base.found, "rot": base.rot, "actions": base.actions}
	if not base.found:
		return m
	var full := Solver.search(L, L.start_cell)
	m["states"] = full.count
	m["dead"] = full.dead
	m["unvisited"] = full.unvisited.size()
	var need := []
	for i in L.doors.size():
		if not search(L, {"frozen": [i]}).found:
			need.append(L.doors[i].id)
	m["need_doors"] = need
	for sw: String in ["no_pull", "no_push", "no_take"]:
		var r := search(L, {sw: true})
		m[sw] = "impossible" if not r.found else str(r.rot)
	var pulls := 0
	var takes := 0
	var streak := 0
	var best := 0
	var last := -1
	for a: Dictionary in base.actions:
		if a.t == "turn":
			if not a.push:
				pulls += 1
			streak = streak + 1 if a.door == last else 1
			last = a.door
			best = maxi(best, streak)
		elif a.t == "detach":
			takes += 1
			last = -1
	m["pulls"] = pulls
	m["takes"] = takes
	m["streak"] = best
	return m


func _report(name: String, L: LevelLogic, text: String) -> void:
	var m := measure(L)
	print("=== %s" % name)
	if text != "":
		print(text)
	if not m.found:
		print("   NOT SOLVABLE")
		return
	print("   cells %d  doors %d  states %d  dead ends %d  unreachable cells %d" % [L.cells.size(), L.doors.size(), m.states, m.dead, m.unvisited])
	print("   shortest: %d turns (%d pulls), knob taken out %d times, longest ride on one door %d turns" % [m.rot, m.pulls, m.takes, m.streak])
	print("   doors that must be turned: %s of %d" % [m.need_doors, L.doors.size()])
	print("   without pulling: %s   without pushing: %s   without ever taking the knob back: %s" % [m.no_pull, m.no_push, m.no_take])
	for line in Solver.describe(L, m.actions):
		print("      " + line)


func _evaluate_dir(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		print("no lab levels in ", dir)
		return
	var files := Array(da.get_files())
	files.sort()
	for f: String in files:
		if not f.ends_with(".txt"):
			continue
		var L := LevelLogic.new()
		L.load_file(dir.path_join(f))
		_report(f, L, "")


# ------------------------------------------------------------------ random small boards
func _make(rng: RandomNumberGenerator, w: int, h: int, nd: int) -> String:
	var rows: Array = []
	for ly in 2 * h + 1:
		var row := []
		for lx in 2 * w + 1:
			var ch := " "
			if ly % 2 == 0 and lx % 2 == 0:
				ch = "+"
			elif ly % 2 == 1 and lx % 2 == 1:
				ch = "l"
			else:
				var border := ly == 0 or ly == 2 * h or lx == 0 or lx == 2 * w
				if border or rng.randf() < 0.5:
					ch = "-" if ly % 2 == 0 else "|"
			row.append(ch)
		rows.append(row)
	var hinges: Array[Vector2i] = []
	var cfg := ""
	var tries := 0
	while hinges.size() < nd and tries < 60:
		tries += 1
		var v := Vector2i(rng.randi_range(1, w - 1), rng.randi_range(1, h - 1))
		var ok := true
		for o in hinges:
			if absi(o.x - v.x) + absi(o.y - v.y) < 2:
				ok = false
		if not ok:
			continue
		hinges.append(v)
		var id := hinges.size()
		var s0 := rng.randi_range(0, 3)
		var k := rng.randi_range(2, 4)
		var slots := ""
		for d in 4:
			var pos: Vector2i = Vector2i(2 * v.x, 2 * v.y) + LevelLogic.DIRV[d]
			var isslot := ((d - s0 + 4) & 3) < k
			if isslot:
				rows[pos.y][pos.x] = "D"
				slots += LevelLogic.DIRNAME[d]
			else:
				rows[pos.y][pos.x] = "-" if d % 2 == 0 else "|"
		rows[2 * v.y][2 * v.x] = str(id)
		cfg += "door %d type=%s start=%s slots=%s\n" % [id, "ccw" if rng.randf() < 0.5 else "cw", slots[rng.randi_range(0, slots.length() - 1)], slots]
	if hinges.size() < nd:
		return ""
	var text := "map\n"
	for row: Array in rows:
		text += "".join(row) + "\n"
	text += "end\n" + cfg
	var a := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
	var b := a
	while b == a:
		b = Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
	text += "phone %d %d\nstart %d %d\n" % [a.x, a.y, b.x, b.y]
	return text


func _generate(n: int, w: int, h: int, nd: int, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var found := []
	for i in n:
		var text := _make(rng, w, h, nd)
		if text == "":
			continue
		var L := LevelLogic.new()
		L.parse(text)
		var base := search(L)
		if not base.found or base.rot < 2:
			continue
		var m := measure(L)
		if m.unvisited > 2 or m.need_doors.size() < L.doors.size():
			continue
		var score: int = m.rot * 2 + (6 if m.no_pull == "impossible" else 0) + (6 if m.no_take == "impossible" else 0) + (3 if m.no_push == "impossible" else 0) + m.streak
		found.append([score, text, m])
	found.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	print("%d boards tried at %dx%d with %d doors, %d kept" % [n, w, h, nd, found.size()])
	for i in mini(4, found.size()):
		var L := LevelLogic.new()
		L.parse(found[i][1])
		_report("candidate %d (score %d)" % [i + 1, found[i][0]], L, found[i][1])
