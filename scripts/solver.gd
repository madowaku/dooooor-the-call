class_name Solver
extends RefCounted
## Exhaustive 0-1 BFS over (player cell, door positions, knob location).
## Minimises the number of door turns. Used by tools/solve.gd and by the autoplay QA bot.

static func _snap(L: LevelLogic) -> Array:
	var p := []
	for d in L.doors:
		p.append(d.pos)
	return [p, L.knob_on]

static func _restore(L: LevelLogic, s: Array) -> void:
	for i in L.doors.size():
		L.doors[i].pos = s[0][i]
	L.knob_on = s[1]

static func search(L: LevelLogic, from_cell: Vector2i, frozen: Array = []) -> Dictionary:
	var init := _snap(L)
	var start_key := L.state_key(from_cell)
	var info := {start_key: {"cell": from_cell, "snap": init, "rot": 0, "prev": "", "act": {"t": "start"}}}
	var dq: Array = [start_key]
	var adj := {}
	var best_goal := ""
	while not dq.is_empty():
		var key: String = dq.pop_front()
		var st: Dictionary = info[key]
		_restore(L, st.snap)
		var cell: Vector2i = st.cell
		if cell == L.phone_cell and best_goal == "":
			best_goal = key
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
				L.knob_on = -1
				nexts.append([cell, _snap(L), 0, {"t": "detach", "door": di}])
				L.knob_on = di
				for r: Array in L.rotations(di):
					var old := L.doors[di].pos
					var push := L.is_push(di, r[1])
					L.doors[di].pos = r[0]
					var nc := L.op_cell(di)
					nexts.append([nc, _snap(L), 1, {"t": "turn", "door": di, "from": old, "pos": r[0], "turn": r[1], "push": push, "to": nc}])
					L.doors[di].pos = old
		adj[key] = []
		for nx: Array in nexts:
			_restore(L, nx[1])
			var nk := L.state_key(nx[0])
			adj[key].append(nk)
			var nr: int = st.rot + nx[2]
			if not info.has(nk) or info[nk].rot > nr:
				info[nk] = {"cell": nx[0], "snap": nx[1], "rot": nr, "prev": key, "act": nx[3]}
				if nx[2] == 0:
					dq.push_front(nk)
				else:
					dq.push_back(nk)
	var radj := {}
	for k: String in adj:
		for nb: String in adj[k]:
			if not radj.has(nb):
				radj[nb] = []
			radj[nb].append(k)
	var can := {}
	var stack := []
	var visited_cells := {}
	for k: String in info:
		visited_cells[info[k].cell] = true
		if info[k].cell == L.phone_cell:
			can[k] = true
			stack.append(k)
	while not stack.is_empty():
		var k: String = stack.pop_back()
		for p: String in radj.get(k, []):
			if not can.has(p):
				can[p] = true
				stack.append(p)
	var unvisited := []
	for c: Vector2i in L.cells:
		if not visited_cells.has(c):
			unvisited.append(c)
	var actions := []
	var k := best_goal
	while k != "" and info.has(k):
		actions.push_front(info[k].act)
		k = info[k].prev
	_restore(L, init)
	return {
		"count": info.size(),
		"found": best_goal != "",
		"rot": info[best_goal].rot if best_goal != "" else -1,
		"actions": actions,
		"dead": info.size() - can.size(),
		"unvisited": unvisited,
	}

static func describe(L: LevelLogic, actions: Array) -> Array[String]:
	var out: Array[String] = []
	var walking := false
	for a: Dictionary in actions:
		match a.t:
			"walk":
				if not walking:
					out.append("walk")
				out[out.size() - 1] = "walk -> %s" % a.to
				walking = true
				continue
			"attach":
				out.append("ATTACH knob to door %d" % L.doors[a.door].id)
			"detach":
				out.append("TAKE knob from door %d" % L.doors[a.door].id)
			"turn":
				out.append("TURN door %d %s->%s (%s), carried to %s" % [L.doors[a.door].id, LevelLogic.DIRNAME[a.from], LevelLogic.DIRNAME[a.pos], "push" if a.push else "pull", a.to])
		walking = false
	return out
