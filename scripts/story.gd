class_name Story
extends Node
## The serial: which chapter is loaded, how one leads to the next, automatic cameras for chapters 2-4,
## and the last scene, where the knob changes hands.

const CHAPTERS := ["res://level/building.txt", "res://level/ch2.txt", "res://level/ch3.txt", "res://level/ch4.txt"]
const SAVE := "user://save.cfg"

static var chapter := 1
static var resume := false
static var bot_done := false
static var marathon := false
static var no_save := false
## the number. one digit is heard in each of the first three receivers.
const NUMBER := [5, 0, 5]
const PULSE_T0 := 1.5
const PULSE_GAP := 0.14
static var heard: Array = [false, false, false]       # QA: play every chapter in one run, through the real transitions

var m                                # the director (main.gd)
var cams: Dictionary = {}             # cell -> [position, look-at, tracking, fov]
var cam_key: Dictionary = {}          # cell -> which stretch of the room it belongs to
var report: Array[String] = []
var solo: Dictionary = {}             # cell -> a camera inside that one cell
var solo_cell := Vector2i(-1, -1)
var solo_hold := 0.0
var worst := 1.0
var other: Human                     # the one who has been knocking
var final_door: Door
var goal_dir := -1
var grille_pt := Vector3.ZERO
var other_grille := Vector3.ZERO
var arrived := false
var at_grille := false
var can_give := false
var handed := false
var sealed := false
var knob_gone := false
var dialing := false
var dial_sel := 5                # the hole the finger is on
var dial_in: Array = []          # digits dialled so far
var dial_wrong := 0
var dial_busy := false


static func level_path() -> String:
	return CHAPTERS[clampi(chapter, 1, CHAPTERS.size()) - 1]

static func saved() -> int:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return 1
	var h = cf.get_value("game", "heard", [false, false, false])
	if h is Array and h.size() == 3:
		heard = [bool(h[0]), bool(h[1]), bool(h[2])]
	return clampi(int(cf.get_value("game", "chapter", 1)), 1, CHAPTERS.size())

static func save(n: int) -> void:
	if no_save:
		return   # QA bots must never touch the player's own progress
	var cf := ConfigFile.new()
	cf.set_value("game", "chapter", n)
	cf.set_value("game", "heard", heard)
	cf.save(SAVE)

static func pulses(digit: int) -> int:
	return 10 if digit == 0 else digit

## when the first pulse of a digit is heard, counted from the start of the line recording
static func pulse_start(digit: int) -> float:
	return PULSE_T0 + 0.25 + 0.09 * pulses(digit) + 0.25

## the digits heard so far, for the pause screen. an unheard one is a dot.
static func memo() -> String:
	var out := ""
	for i in 3:
		out += (str(NUMBER[i]) if heard[i] else "・") + ("  " if i < 2 else "")
	return out

## follow the receiver: light one dot per pulse, then let the numeral come up for a moment
func line_tick(t: float) -> void:
	var hud = m.hud
	if t < 0.0 or chapter > 3 or m.lab or is_final():
		hud.num_alpha = 0.0
		hud.num_dots = 0
		return
	var digit: int = NUMBER[chapter - 1]
	var n := pulses(digit)
	var t0 := pulse_start(digit)
	var t1 := t0 + (n - 1) * PULSE_GAP
	hud.num_digit = digit
	hud.num_total = n
	hud.num_dots = clampi(int(floor((t - t0) / PULSE_GAP)) + 1, 0, n) if t >= t0 else 0
	var a := 0.0
	if t > t1 + 0.35:
		a = clampf((t - t1 - 0.35) / 0.5, 0.0, 1.0) * clampf((t1 + 3.0 - t) / 0.9, 0.0, 1.0)
		if not heard[chapter - 1]:
			heard[chapter - 1] = true
			save(chapter)
	hud.num_alpha = a
	if t > t1 + 3.2:
		hud.num_dots = 0
	if not m.cam.is_position_behind(m.human.right_hand_global()):
		hud.num_pos = m.cam.unproject_position(m.human.right_hand_global())


func is_final() -> bool:
	return m.meta != null and m.meta.goal == "grille"


# ------------------------------------------------------------------ world
func setup_world() -> void:
	if m.lab:
		return
	_place_cams()
	if is_final():
		_setup_final()

func room_cells() -> Dictionary:
	var out := {}
	for c: Vector2i in m.L.cells:
		var r: String = m.L.cells[c]
		if not out.has(r):
			out[r] = []
		out[r].append(c)
	return out

## a room is cut into stretches of at most three cells, each with its own fixed camera:
## a long corridor seen from one end always hides the end the camera stands in.
func _chunks(cells: Array) -> Array:
	var lo := Vector2i(999, 999)
	var hi := Vector2i(-999, -999)
	for c: Vector2i in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var w := hi.x - lo.x + 1
	var h := hi.y - lo.y + 1
	var rect := cells.size() == w * h
	var out := []
	if rect and maxi(w, h) <= 3:
		return [cells]
	var along_x := w >= h if rect else true
	# rows (or columns) first, then pieces of at most three along them
	var lines := {}
	for c: Vector2i in cells:
		var k := c.y if along_x else c.x
		if rect and mini(w, h) > 1:
			k = 0
		if not lines.has(k):
			lines[k] = []
		lines[k].append(c)
	for k: int in lines:
		var line: Array = lines[k]
		line.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a.x < b.x) if along_x else (a.y < b.y))
		var span: int = (line[-1].x - line[0].x + 1) if along_x else (line[-1].y - line[0].y + 1)
		var parts := int(ceil(span / 3.0))
		var per := int(ceil(float(span) / parts))
		var groups := {}
		for c: Vector2i in line:
			var idx: int = ((c.x - line[0].x) if along_x else (c.y - line[0].y)) / per
			if not groups.has(idx):
				groups[idx] = []
			groups[idx].append(c)
		for g: int in groups:
			out.append(groups[g])
	return out

## every stretch gets the camera that hides least. chapter 1 keeps its hand-placed cameras
## wherever they already show every doorway.
func _place_cams() -> void:
	CamAudit.leaves = []
	for d: LevelLogic.DoorDef in m.L.doors:
		var hp := Building.vertex_pos(d.hinge)
		for pos: int in d.slots:
			var dv := Building.dir_vec(pos)
			CamAudit.leaves.append([Vector2(hp.x + dv.x * 0.16, hp.z + dv.z * 0.16), Vector2(hp.x + dv.x * 1.64, hp.z + dv.z * 1.64)])
	cams.clear()
	cam_key.clear()
	report.clear()
	var rooms := room_cells()
	for r: String in rooms:
		var rest: Array = []
		for c: Vector2i in rooms[r]:
			if m.meta == null and m.CELL_CAMS.has(c):
				cams[c] = m.CELL_CAMS[c]
				cam_key[c] = c
				_note(r, [c], m.CELL_CAMS[c], "hand")
			else:
				rest.append(c)
		if rest.is_empty():
			continue
		var hand: Array = []
		if m.meta != null and m.meta.cams.has(r):
			hand = m.meta.cams[r]
		elif m.meta == null and m.CAMS.has(r):
			hand = m.CAMS[r]
		if not hand.is_empty():
			var res := CamAudit.score(hand, rest, CamAudit.features(m.L, m.B, rest))
			if res.hidden.is_empty() and res.score >= 0.8:
				for c: Vector2i in rest:
					cams[c] = hand
					cam_key[c] = rest[0]
				_note(r, rest, hand, "hand")
				continue
		var todo: Array = _chunks(rest)
		while not todo.is_empty():
			var chunk: Array = todo.pop_front()
			var cfg := CamAudit.best(m.L, m.B, chunk)
			var res2 := CamAudit.score(cfg, chunk, CamAudit.features(m.L, m.B, chunk))
			if not res2.hidden.is_empty() and chunk.size() > 1:
				# still hiding a doorway: cut the stretch in two and try again
				var half := int(ceil(chunk.size() / 2.0))
				todo.append(chunk.slice(0, half))
				todo.append(chunk.slice(half))
				continue
			for c: Vector2i in chunk:
				cams[c] = cfg
				cam_key[c] = chunk[0]
			_note(r, chunk, cfg, "auto")

func _note(room: String, cells: Array, cfg: Array, how: String) -> void:
	var res := CamAudit.score(cfg, cells, CamAudit.features(m.L, m.B, cells))
	var hid := []
	for f: Dictionary in res.hidden:
		hid.append("%s at %s" % [f.kind, f.cell])
	report.append("CAM ch%d room %s %s  %s  shows %3d%%  fov %.0f  hidden: %s" % [chapter, room, str(cells[0]), how, int(round(res.score * 100.0)), cfg[3], hid])
	worst = minf(worst, res.score)

func audit() -> void:
	for line: String in report:
		print(line)
	print("CAMAUDIT ch%d worst camera shows %d%%" % [chapter, int(round(worst * 100.0))])

func cam_for(cell: Vector2i) -> Array:
	return cams.get(cell, [Vector3(1.5, 2.4, 1.5), Vector3.ZERO, 0.3, 60.0])

## is the player hidden from this camera right now, by a door leaf where it really stands,
## or by having walked out of the frame?
func hidden_from(cfg: Array, p: Vector3) -> bool:
	var head := p + Vector3(0, 1.5, 0)
	for d: Door in m.doors:
		if d.turning:
			continue
		var dv := Building.dir_vec(d.def.pos)
		var hp := d.global_position
		if CamAudit.leaf_blocks(cfg[0], head, Vector2(hp.x + dv.x * 0.16, hp.z + dv.z * 0.16), Vector2(hp.x + dv.x * 1.64, hp.z + dv.z * 1.64)):
			return true
	var look: Vector3 = (cfg[1] as Vector3).lerp(p + Vector3(0, 1.0, 0), cfg[2])
	return not CamAudit.on_screen(cfg[0], look, cfg[3], head)

## QA: with the camera as it really is this frame, can the player be seen?
func lost() -> bool:
	var head: Vector3 = m.player.global_position + Vector3(0, 1.5, 0)
	if m.cam.is_position_behind(head):
		return true
	var sp: Vector2 = m.cam.unproject_position(head)
	if sp.x < 8.0 or sp.x > 504.0 or sp.y < 8.0 or sp.y > 376.0:
		return true
	for d: Door in m.doors:
		var dv := Building.dir_vec(d.def.pos)
		var hp := d.global_position
		if CamAudit.leaf_blocks(m.cam.global_position, head, Vector2(hp.x + dv.x * 0.16, hp.z + dv.z * 0.16), Vector2(hp.x + dv.x * 1.64, hp.z + dv.z * 1.64)):
			return true
	return false

## the camera to use this frame. normally the one placed for this stretch of the room; but the player
## must never be lost, so when that camera cannot see them, a camera inside their own cell takes over
## (a leaf stands on the edge of a cell, never between two points inside one).
func view_for(p: Vector3) -> Array:
	var cell := Building.world_to_cell(p)
	var cfg := cam_for(cell)
	var want := hidden_from(cfg, p)
	if want:
		solo_cell = cell
		solo_hold = 1.2
	elif solo_hold > 0.0 and cell == solo_cell:
		want = true
	else:
		solo_cell = Vector2i(-1, -1)
	if not want:
		return cfg
	if not solo.has(cell):
		var keep: Array = CamAudit.leaves
		solo[cell] = CamAudit.best(m.L, m.B, [cell])
		CamAudit.leaves = keep
	return solo[cell]

func key_of(cell: Vector2i) -> Vector2i:
	if cell == solo_cell:
		return cell + Vector2i(1000, 0)
	return cam_key.get(cell, Vector2i(-1, -1))

func plan_cam() -> Array:
	if m.meta == null:
		return [Vector3(7.5, 24.5, 9.5), Vector3(7.5, 0, 9.0), 43.0]
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c: Vector2i in m.L.cells:
		lo = lo.min(Vector2(c))
		hi = hi.max(Vector2(c) + Vector2.ONE)
	lo *= Building.CELL
	hi *= Building.CELL
	var h := maxf((hi.y - lo.y) / 0.788, (hi.x - lo.x) / 1.05) * 1.1 + 2.8
	var c2 := (lo + hi) * 0.5
	return [Vector3(c2.x, h, c2.y + 0.5), Vector3(c2.x, 0, c2.y), 43.0]

func enter_chapter() -> void:
	m.state = m.St.PLAY
	m.hud.mode = "play"
	m.hud.fade = 1.0
	create_tween().tween_property(m.hud, "fade", 0.0, 2.6)
	m.intro_done = true
	m.first_attach_done = true
	m.hud.knob_known = true
	m.phone_seen = is_final()
	m.title_human.visible = false
	m.cam_override = false
	m.env.fog_density = 0.028
	m.env.background_color = Color(0.012, 0.014, 0.02)
	m.cam_room = ""
	m._update_room(true)

func sees_phone(cell: Vector2i) -> bool:
	return m.L.cells.get(cell, "") == m.L.cells.get(m.L.phone_cell, "?")

## chapters 2 and 3: the first sight of the telephone, from wherever the player came in
func discover() -> void:
	m.phone_seen = true
	m.state = m.St.BUSY
	m.hud.mode = "none"
	m.human.pose = "idle"
	m.human.walk_speed = 0.0
	m.human.has_look = true
	var ph: Vector3 = m.B.phone_pos + Vector3(0, 0.75, 0)
	m.human.look_target = ph
	m.cam_override = true
	var pp: Vector3 = m.player.global_position
	var away := Vector3(pp.x - ph.x, 0, pp.z - ph.z)
	if away.length() < 0.5:
		away = Vector3(0, 0, 1)
	var side := Vector3(-away.z, 0, away.x).normalized()
	var cc := Building.cell_center(Building.world_to_cell(pp))
	var cp: Vector3 = pp + away.normalized() * 0.7 + side * 0.75
	cp.x = clampf(cp.x, cc.x - 1.25, cc.x + 1.25)
	cp.z = clampf(cp.z, cc.z - 1.25, cc.z + 1.25)
	m.cam.global_position = cp + Vector3(0, 1.7, 0)
	m.cam.look_at(ph)
	m.cam.fov = 52.0
	create_tween().tween_property(m.cam, "fov", 40.0, 2.6).set_trans(Tween.TRANS_SINE)
	if m.bot:
		await m.wait(1.5)
		await m._shot("29_discovery")
		await m.wait(1.0)
	else:
		await m.wait(2.8)
	m.cam_override = false
	m.hud.mode = "play"
	m._update_room(true)
	m.state = m.St.PLAY

## the telephone has been answered and the picture has gone dark
func advance() -> void:
	if m.bot and not marathon:
		bot_done = true
		return
	chapter = mini(chapter + 1, CHAPTERS.size())
	resume = true
	save(chapter)
	m._restart()


# ------------------------------------------------------------------ the last room
func _setup_final() -> void:
	for d: Door in m.doors:
		if d.def.id == m.meta.final_door:
			final_door = d
	var goal: Vector2i = m.L.phone_cell
	for d in 4:
		if m.L.edge_type(goal, d) == LevelLogic.Edge.GRILLE:
			goal_dir = d
	var dv := Building.dir_vec(goal_dir)
	grille_pt = Building.cell_center(goal) + dv * 0.8
	other_grille = Building.cell_center(goal + LevelLogic.DIRV[goal_dir]) - dv * 0.75
	other = Human.new()
	m.world.add_child(other)
	other.position = final_door.rider_world(true)
	other.rotation.y = final_door.rider_yaw(true)
	var oc := Building.world_to_cell(other.position)
	other.set_layers(m.B.room_bit[m.L.cells[oc]])

func phone_usable() -> bool:
	return not is_final() or sealed

func _process(_delta: float) -> void:
	solo_hold = maxf(0.0, solo_hold - _delta)
	if m == null or not is_final() or other == null:
		return
	if not arrived:
		# both palms on the inside of a door that has no hole on that side
		other.pose = "thud" if m.hud.ring_env > 0.5 else "idle"
	if dialing and not dial_busy and not m.bot:
		# the holes run 1 2 3 ... 9 0 round the dial
		if Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("move_down"):
			dial_sel = (dial_sel % 10) + 1 if dial_sel != 0 else 1
			if dial_sel == 10:
				dial_sel = 0
			m.sfx("knob_turn", -16.0, 1.6)
		elif Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_up"):
			dial_sel = 0 if dial_sel == 1 else (9 if dial_sel == 0 else dial_sel - 1)
			m.sfx("knob_turn", -16.0, 1.6)
		m.hud.dial_sel = dial_sel

## called every frame of free play in the last chapter
func scan(pc: Vector2i, p: Vector3) -> void:
	can_give = false
	if not is_final() or handed:
		return
	if pc == m.L.phone_cell and not arrived:
		_arrive()
	if at_grille and pc == m.L.phone_cell and Vector2(p.x - grille_pt.x, p.z - grille_pt.z).length() < 1.3 and m.L.knob_on == -1:
		can_give = true
		m.hud.prompt_back = true
		m.hud.prompt_act = false
		m.human.has_look = true
		m.human.look_target = other.global_position + Vector3(0, 1.55, 0)

func _arrive() -> void:
	arrived = true
	# the knocking stops. whoever it is has heard somebody come in.
	m.bell_stopped = true
	m.bell.stop()
	m.bell_wall.stop()
	await m.wait(1.4)
	other.pose = "walk"
	other.walk_speed = 1.0
	var yaw := atan2(-(other_grille.x - other.position.x), -(other_grille.z - other.position.z))
	other.rotation.y = yaw
	var tw := create_tween()
	tw.tween_property(other, "position", other_grille, 2.4)
	await tw.finished
	var dv := Building.dir_vec(goal_dir)
	other.rotation.y = atan2(dv.x, dv.z)
	other.pose = "idle"
	other.walk_speed = 0.0
	other.has_look = true
	other.look_target = m.player.global_position + Vector3(0, 1.5, 0)
	at_grille = true

func on_back() -> bool:
	if can_give and m.state == m.St.PLAY:
		handover()
		return true
	return false

## the only move in the game that cannot be taken back
func handover() -> void:
	handed = true
	can_give = false
	m.state = m.St.BUSY
	m.hud.prompt_back = false
	m.hud.prompt_act = false
	var dv := Building.dir_vec(goal_dir)
	var yaw := atan2(-dv.x, -dv.z)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(m.player, "global_position", grille_pt, 0.5)
	tw.tween_method(func(t: float) -> void: m.player.rotation.y = lerp_angle(m.player.rotation.y, yaw, t), 0.0, 1.0, 0.5)
	await tw.finished
	m.human.pose = "pocket"
	m.human.show_knob(true)
	await m.wait(1.3)
	m.human.pose = "reach"
	other.pose = "reach"
	await m.wait(0.8)
	m.sfx("knob_ting", -5.0)
	m.human.show_knob(false)
	other.show_knob(true)
	knob_gone = true
	m.hud.knob_blink = 1.4
	await m.wait(1.0)
	m.human.pose = "idle"
	other.pose = "hold"
	other.has_look = false
	await m.wait(1.2)
	# the other one goes to the door. it has a hole on that side.
	var home := final_door.rider_world(true)
	other.rotation.y = atan2(-(home.x - other.position.x), -(home.z - other.position.z))
	other.pose = "walk"
	other.walk_speed = 1.0
	var tw2 := create_tween()
	tw2.tween_property(other, "position", home, 2.2)
	await tw2.finished
	other.rotation.y = final_door.rider_yaw(true)
	other.walk_speed = 0.0
	other.pose = "reach"
	await m.wait(0.6)
	m.sfx("knob_insert", -7.0)
	other.show_knob(false)
	final_door.set_knob(true)
	# watch the doorway we came in by
	var goal: Vector2i = m.L.phone_cell
	var gate := Vector3.ZERO
	for d in 4:
		if m.L.edge_type(goal, d) == LevelLogic.Edge.SLOT:
			gate = m.B.portal_center(LevelLogic.edge_key(goal, d))
	var cc := Building.cell_center(goal)
	m.cam_override = true
	m.cam.global_position = cc + (cc - gate).normalized() * 1.1 + Vector3(0.55, 1.55, 0)
	m.cam.look_at(gate + Vector3(0, 1.0, 0))
	m.cam.fov = 62.0
	m.human.has_look = true
	m.human.look_target = gate + Vector3(0, 1.2, 0)
	m.player.rotation.y = atan2(-(gate.x - grille_pt.x), -(gate.z - grille_pt.z))
	await m.wait(1.2)
	m.sfx("knob_turn", -7.0)
	await m.wait(0.4)
	m.sfx("door_move", -2.0, 0.96)
	m.sfx("door_squeak", -17.0, 0.9)
	var np := -1
	var turn := 0
	for r: Array in m.L.rotations(final_door.index):
		np = r[0]
		turn = r[1]
	final_door.turn(np, turn, 2.6)
	while final_door.turning:
		other.global_position = final_door.rider_world(true)
		other.rotation.y = final_door.rider_yaw(true)
		other.pose = "push"
		m.field.update()
		await get_tree().process_frame
	other.global_position = final_door.rider_world(true)
	other.pose = "hold"
	m.sfx("door_seat", 0.0)
	m.cam_shake = 0.06
	await m.wait(1.6)
	m.sfx("knob_remove", -9.0)
	final_door.set_knob(false)
	await m.wait(0.9)
	for i in 6:
		m.sfx("step_wood_%d" % (i % 5), -14.0 - 3.2 * i, 0.95)
		await m.wait(0.5)
	other.visible = false
	await m.wait(1.5)
	m.cam_override = false
	m.human.has_look = false
	m._update_room(true)
	sealed = true
	m.state = m.St.PLAY

func on_phone() -> bool:
	if not is_final():
		return false
	if sealed and not dialing:
		start_dial()
	return true

func start_dial() -> void:
	m.state = m.St.BUSY
	m.hud.prompt_act = false
	m.hud.mode = "none"
	var stand: Vector3 = m.B.phone_pos + Vector3(0, 0, 0.66)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(m.player, "global_position", stand, 0.6)
	tw.tween_method(func(t: float) -> void: m.player.rotation.y = lerp_angle(m.player.rotation.y, 0.0, t), 0.0, 1.0, 0.6)
	await tw.finished
	m.cam_override = true
	# from whichever side keeps the camera inside this room
	var cx := Building.cell_center(Building.world_to_cell(m.B.phone_pos)).x
	var sx := 1.3 if m.B.phone_pos.x + 1.3 < cx + 1.35 else -1.3
	m.cam.global_position = m.B.phone_pos + Vector3(sx, 1.02, 0.3)
	m.cam.look_at(m.B.phone_pos + Vector3(0.0, 0.84, 0.3))
	m.cam.fov = 42.0
	m.human.pose = "reach"
	await m.wait(0.8)
	m.sfx("receiver_lift", 0.0)
	m.B.phone_handset.visible = false
	m.human.show_handset(true)
	m.human.pose = "phone"
	await m.wait(1.2)
	m.hud.mode = "play"
	m.hud.dial_ui = true
	m.hud.dial_sel = dial_sel
	m.hud.dial_in = dial_in
	dialing = true

## Z: put a finger in the chosen hole and turn. the dial runs back, one pulse for each step.
func dial_press() -> void:
	if dialing and not dial_busy:
		dial_digit(dial_sel)

## X: put the receiver down for a moment and start the number again
func dial_erase() -> void:
	if dialing and not dial_busy and not dial_in.is_empty():
		dial_in.clear()
		m.hud.dial_in = dial_in
		m.sfx("line_cut", -10.0)

func dial_digit(d: int) -> void:
	if dial_busy or not dialing:
		return
	dial_busy = true
	var n := pulses(d)
	var wind := 0.3 + 0.07 * n
	var back := 0.25 + 0.1 * n
	m.sfx("dial_wind" if m.streams.has("dial_wind") else "knob_turn", -4.0, clampf(0.55 / wind, 0.45, 1.3))
	var tw := create_tween()
	tw.tween_property(m.hud, "dial_spin", float(n), wind)
	await tw.finished
	await m.wait(0.12)
	m.sfx("dial_return" if m.streams.has("dial_return") else "knob_turn", -4.0, clampf(1.0 / back, 0.6, 1.6))
	var tw2 := create_tween()
	tw2.tween_property(m.hud, "dial_spin", 0.0, back)
	await tw2.finished
	dial_in.append(d)
	m.hud.dial_in = dial_in
	await m.wait(0.35)
	if dial_in.size() >= 3:
		if dial_in == NUMBER:
			dialing = false
			m.hud.dial_ui = false
			_finish()
			return
		# no such number
		await m.wait(0.6)
		m.sfx("line_dead" if m.streams.has("line_dead") else "line_cut", -8.0)
		m.hud.dial_bad = 1.2
		await m.wait(1.7)
		dial_in.clear()
		m.hud.dial_in = dial_in
		dial_wrong += 1
		if dial_wrong >= 2:
			await _hint()
	dial_busy = false

## after two wrong numbers the dead line gives the number back: three groups of pulses
func _hint() -> void:
	if m.streams.has("line_hint"):
		m.sfx("line_hint", -6.0)
	var at := 0.5
	var t := 0.0
	var groups := [0, 0, 0]
	m.hud.hint = groups
	for g in 3:
		var n := pulses(NUMBER[g])
		var r0 := at + 0.25 + 0.09 * n + 0.25
		await m.wait(r0 - t)
		t = r0
		for i in n:
			groups[g] = i + 1
			m.hud.hint = groups
			await m.wait(PULSE_GAP)
			t += PULSE_GAP
		at = r0 + n * PULSE_GAP + 0.75
	await m.wait(2.5)
	m.hud.hint = []

func _finish() -> void:
	m.hud.mode = "none"
	await m.wait(2.2)
	# somewhere far below, a bell that has rung before
	var far := AudioStreamPlayer.new()
	far.stream = m.streams["far_bell1"] if m.streams.has("far_bell1") else m.streams["bell_ring"]
	far.volume_db = -9.0 if m.streams.has("far_bell1") else -30.0
	add_child(far)
	far.play()
	m.hud.echo_far = true
	await m.wait(3.2)
	var pc := plan_cam()
	m.env.fog_density = 0.0
	m.cam.global_position = pc[0]
	m.cam.look_at(pc[1], Vector3(0, 0, -1))
	m.cam.fov = pc[2]
	await m.wait(3.0)
	var tw := create_tween()
	tw.tween_property(m.hud, "fade", 1.0, 4.0)
	await tw.finished
	await m.wait(1.5)
	save(1)
	if marathon:
		print("MARATHON OK: all four chapters and the last scene, in one run")
		get_tree().quit(0)
		return
	if m.bot:
		bot_done = true
		return
	chapter = 1
	resume = false
	m._restart()


# ------------------------------------------------------------------ QA
func bot_finish(shots: bool) -> bool:
	bot_done = false
	if m.state == m.St.DOOR:
		m._on_act()
		await m._bot_until(func() -> bool: return m.state == m.St.PLAY)
	if not is_final():
		await m._bot_goto(m.B.phone_pos + Vector3(0, 0, 0.9))
		await get_tree().process_frame
		await get_tree().process_frame
		if shots:
			await m._shot("30_phone_room")
		if not m.near_phone:
			m.bot_fail = "phone not in reach"
			return false
		m._on_act()
		if shots:
			await m.wait(4.2)
			await m._shot("31_pickup")
			# sound does not speed up with the bot's clock: wait for the numeral itself
			if not await m._bot_until(func() -> bool: return m.hud.num_alpha > 0.7, 60.0):
				m.bot_fail = "the digit never appeared"
				return false
			await m._shot("32_number")
			if not heard[chapter - 1]:
				m.bot_fail = "the digit was not remembered"
				return false
			await m.wait(6.0)
			await m._shot("33_plan")
		return await m._bot_until(func() -> bool: return bot_done, 90.0)
	if m.L.knob_on != -1:
		# random play can arrive with the knob still sitting in a door: go back for it, on foot
		var di: int = m.L.knob_on
		var every := []
		for i in m.L.doors.size():
			every.append(i)
		var keep: Vector2i = m.L.phone_cell
		m.L.phone_cell = m.L.op_cell(di)
		var r1 := Solver.search(m.L, Building.world_to_cell(m.player.global_position), every)
		m.L.phone_cell = keep
		if not r1.found or not await m._bot_play(r1.actions, false) or not await m._bot_to_door(m.doors[di]):
			m.bot_fail = "the knob was left in a door that cannot be walked back to"
			return false
		m._on_back()
		await m._bot_until(func() -> bool: return m.state == m.St.PLAY and m.L.knob_on == -1, 20.0)
		var r2 := Solver.search(m.L, Building.world_to_cell(m.player.global_position), every)
		if not r2.found or not await m._bot_play(r2.actions, false):
			m.bot_fail = "could not walk back to the grille"
			return false
	await m._bot_goto(Building.cell_center(m.L.phone_cell))
	if not await m._bot_until(func() -> bool: return at_grille, 20.0):
		m.bot_fail = "nobody came to the grille"
		return false
	await m._bot_goto(grille_pt)
	await get_tree().process_frame
	await get_tree().process_frame
	if shots:
		await m._shot("40_grille")
	if not can_give:
		m.bot_fail = "cannot hand the knob over"
		return false
	m._on_back()
	if shots:
		await m.wait(3.0)
		await m._shot("41_handover")
		await m.wait(9.5)
		await m._shot("42_door_turns")
	if not await m._bot_until(func() -> bool: return sealed, 60.0):
		m.bot_fail = "the last door never closed"
		return false
	# the way out must really be shut
	var res := Solver.search(m.L, m.L.phone_cell)
	if res.count > 2:
		m.bot_fail = "the player can still leave (%d states)" % res.count
		return false
	await m._bot_goto(m.B.phone_pos + Vector3(0, 0, 0.9))
	await get_tree().process_frame
	await get_tree().process_frame
	if shots:
		await m._shot("43_shut_in")
	if not m.near_phone:
		m.bot_fail = "telephone not in reach"
		return false
	m._on_act()
	if not await m._bot_until(func() -> bool: return dialing, 20.0):
		m.bot_fail = "could not start dialling"
		return false
	if shots:
		await m._shot("44_dial")
	# a wrong number first: the line must go dead and the entry must start again
	for d: int in [1, 2, 3]:
		dial_digit(d)
		await get_tree().process_frame
		await m._bot_until(func() -> bool: return not dial_busy, 20.0)
	if dialing == false or not dial_in.is_empty():
		m.bot_fail = "a wrong number was not rejected"
		return false
	for d: int in NUMBER:
		dial_digit(d)
		await get_tree().process_frame
		if shots and d == 0:
			await m.wait(0.5)
			await m._shot("45_dialling")
		await m._bot_until(func() -> bool: return not dial_busy or not dialing, 20.0)
	if dialing:
		m.bot_fail = "505 did not connect"
		return false
	return await m._bot_until(func() -> bool: return bot_done, 60.0)
