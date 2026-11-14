class_name Story
extends Node
## The serial: which chapter is loaded, how one leads to the next, automatic cameras for chapters 2-4,
## and the last scene, where the knob changes hands.

const CHAPTERS := ["res://level/building.txt", "res://level/ch2.txt", "res://level/ch3.txt", "res://level/ch4.txt"]
const SAVE := "user://save.cfg"

static var chapter := 1
static var resume := false
static var bot_done := false
static var marathon := false       # QA: play every chapter in one run, through the real transitions

var m                                # the director (main.gd)
var cams: Dictionary = {}
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
var dial_n := 0
var dial_released := true
var dial_busy := false


static func level_path() -> String:
	return CHAPTERS[clampi(chapter, 1, CHAPTERS.size()) - 1]

static func saved() -> int:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return 1
	return clampi(int(cf.get_value("game", "chapter", 1)), 1, CHAPTERS.size())

static func save(n: int) -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "chapter", n)
	cf.save(SAVE)


func is_final() -> bool:
	return m.meta != null and m.meta.goal == "grille"


# ------------------------------------------------------------------ world
func setup_world() -> void:
	if m.meta == null:
		return
	_auto_cams()
	if is_final():
		_setup_final()

## one camera per room, always in the south-east corner, looking north or west:
## whatever room you walk into, "up" on the screen is never south.
func _auto_cams() -> void:
	var lo := {}
	var hi := {}
	for c: Vector2i in m.L.cells:
		var r: String = m.L.cells[c]
		if not lo.has(r):
			lo[r] = c
			hi[r] = c
		lo[r] = Vector2i(mini(lo[r].x, c.x), mini(lo[r].y, c.y))
		hi[r] = Vector2i(maxi(hi[r].x, c.x), maxi(hi[r].y, c.y))
	for r: String in lo:
		var x0: float = lo[r].x * Building.CELL
		var z0: float = lo[r].y * Building.CELL
		var x1: float = (hi[r].x + 1) * Building.CELL
		var z1: float = (hi[r].y + 1) * Building.CELL
		var w := x1 - x0
		var d := z1 - z0
		var pos := Vector3(x1 - 0.42, 2.48, z1 - 0.42)
		var look := Vector3((x0 + x1) * 0.5, 0.75, (z0 + z1) * 0.5)
		var fov := 74.0
		var track := 0.25
		if d > w + 0.1:
			look = Vector3(lerpf(x1, x0, 0.6), 0.9, lerpf(z1, z0, 0.62))
			fov = 60.0
			track = 0.4
		elif w > d + 0.1:
			look = Vector3(lerpf(x1, x0, 0.62), 0.9, lerpf(z1, z0, 0.6))
			fov = 60.0
			track = 0.4
		elif w > 3.1:
			fov = 68.0
			look = Vector3(lerpf(x1, x0, 0.6), 0.7, lerpf(z1, z0, 0.6))
		cams[r] = [pos, look, track, fov]
	for r: String in m.meta.cams:
		cams[r] = m.meta.cams[r]

func cam_cfg(room: String) -> Array:
	return cams.get(room, [Vector3(1.5, 2.4, 1.5), Vector3.ZERO, 0.3, 60.0])

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
	if m == null or not is_final() or other == null:
		return
	if not arrived:
		# both palms on the inside of a door that has no hole on that side
		other.pose = "thud" if m.hud.ring_env > 0.5 else "idle"
	if dialing and not dial_busy and not m.bot:
		var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if iv.length() < 0.3:
			dial_released = true
		elif dial_released and iv.length() > 0.7:
			dial_released = false
			dial_step()

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
	m.hud.dial_n = 0
	dial_released = false
	dialing = true

## one turn of the dial: the same push of the stick that used to turn a door
func dial_step() -> void:
	if dial_busy or not dialing:
		return
	dial_busy = true
	dial_n += 1
	m.hud.dial_n = dial_n
	m.sfx("dial_wind" if m.streams.has("dial_wind") else "knob_turn", -4.0)
	await m.wait(0.6)
	m.sfx("dial_return" if m.streams.has("dial_return") else "knob_turn", -4.0)
	await m.wait(1.1)
	dial_busy = false
	if dial_n >= 3:
		dialing = false
		_finish()

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
			await m.wait(4.0)
			await m._shot("32_silence")
			await m.wait(9.0)
			await m._shot("33_plan")
		return await m._bot_until(func() -> bool: return bot_done, 90.0)
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
	for i in 3:
		dial_step()
		await m._bot_until(func() -> bool: return not dial_busy, 10.0)
	return await m._bot_until(func() -> bool: return bot_done, 60.0)
