extends Node
## DOOOOOR: THE CALL -- director script: flow, cameras, interaction, sound mix, QA bot.

const VW := 512
const VH := 384
const SPEED := 2.5
const EXT := Vector3(60, 0, 0)

enum St { TITLE, TRANSITION, PLAY, BUSY, DOOR, ENDING, END, LABMENU, LABDONE }

## DOOOOOR LAB: bare test boards for trying a puzzle idea by hand before any building is made for it.
## [file in level/lab, name on the list]
const LAB := [
	["b_ride_twice", "01  運ばれる"],
	["c_come_back", "02  戻って回す"],
	["d_where_to_leave", "03  ノブを抜く"],
]
static var booted := false
static var lab_menu := false
static var lab_file := ""
static var lab_sel := 0
static var lab_results := {}
var lab := false
var lab_cfg: Array = []
var lab_min := 0
var lab_t := 0.0
var lab_turns := 0
var lab_log: Array[String] = []

## room -> [camera position, base look-at, tracking amount, fov]
const CAMS := {
	"s": [Vector3(2.5, 2.3, 17.55), Vector3(1.3, 1.0, 12.4), 0.3, 56.0],
	"w": [Vector3(2.55, 2.45, 3.5), Vector3(1.2, 0.9, 9.8), 0.4, 60.0],
	"n": [Vector3(11.55, 2.45, 0.5), Vector3(4.5, 0.9, 1.7), 0.45, 58.0],
	"e": [Vector3(14.6, 2.6, 0.4), Vector3(13.2, 0.6, 2.0), 0.15, 80.0],
	"c": [Vector3(14.5, 2.45, 11.55), Vector3(13.1, 0.9, 5.6), 0.4, 60.0],
	"l": [Vector3(11.5, 2.5, 14.5), Vector3(6.4, 0.7, 10.6), 0.3, 62.0],
	"x": [Vector3(5.55, 2.5, 14.55), Vector3(4.1, 0.7, 12.9), 0.3, 68.0],
	"r": [Vector3(5.55, 2.5, 3.5), Vector3(4.0, 0.8, 5.0), 0.3, 68.0],
	"k": [Vector3(11.5, 2.4, 3.5), Vector3(9.4, 1.0, 5.0), 0.3, 66.0],
	"p": [Vector3(3.5, 2.45, 8.55), Vector3(7.2, 0.7, 5.3), 0.3, 62.0],
}

## the telephone gets its own cameras: the long look down the mats, then the alcove itself
const NO_CELL := Vector2i(-1, -1)
const DISCOVER_CAM := [Vector3(7.9, 1.75, 8.8), Vector3(7.5, 0.9, 4.0), 0.12, 46.0]
const CELL_CAMS := {
	Vector2i(2, 1): [Vector3(8.6, 1.6, 5.8), Vector3(7.35, 0.85, 3.75), 0.2, 52.0],
}

## how each room answers: [reverb size, damping, extra wet on the bell, wet on footsteps and doors]
const ROOM_AC := {
	"s": [0.78, 0.35, 0.0, 0.2], "w": [0.8, 0.3, 0.02, 0.22], "c": [0.8, 0.22, 0.03, 0.26],
	"n": [0.7, 0.5, 0.0, 0.14], "e": [0.6, 0.5, 0.0, 0.14],
	"l": [0.6, 0.78, -0.03, 0.07], "x": [0.35, 0.3, 0.05, 0.24],
	"r": [0.55, 0.06, 0.12, 0.44], "k": [0.45, 0.5, 0.0, 0.12], "p": [0.4, 0.86, -0.04, 0.05],
}

## chapters 2-4 take the answer of a room from what its floor is made of
const AC_BY := {"concrete": [0.78, 0.3, 0.02, 0.22], "wood": [0.66, 0.5, 0.0, 0.14], "carpet": [0.5, 0.8, -0.03, 0.06], "tile": [0.56, 0.06, 0.12, 0.44]}
const EXTRA_SOUNDS := ["bell2_ring", "bell2_wall", "bell2_tail", "bell3_ring", "bell3_wall", "bell3_tail", "bell3_pipe",
	"knock_ring", "knock_wall", "pipe_tick", "line2", "line3", "dial_wind", "dial_return", "far_bell1", "rain_loop", "drip", "boiler_hum",
	"line_a1", "line_a2", "line_a3", "line_hint", "line_dead"]

var L: LevelLogic
var meta: LevelMeta
var story: Story
var ring_period := 3.0
var ring_len := 1.05
var src_db := 0.0
var wall_gain := 0.0
var line_period := 3.0
var line_len := 1.0
var bell_pipe: AudioStreamPlayer3D
var pipe_s := 0.0
var vp: SubViewport
var screen: TextureRect
var post: ShaderMaterial
var world: Node3D
var B: Building
var doors: Array[Door] = []
var player: CharacterBody3D
var human: Human
var title_human: Human
var cam: Camera3D
var listener: AudioListener3D
var hud: Hud
var field: SoundField
var env: Environment

var state: St = St.TITLE
var clock := 0.0
var intro_done := false
var first_attach_done := false
var cur_door: Door = null
var cam_room := ""
var cam_cell := NO_CELL
var phone_seen := false
var aid_mode := 0
var line: AudioStreamPlayer
var cam_look := Vector3.ZERO
var cam_override := false
var cam_shake := 0.0
var move_basis := Basis.IDENTITY
var move_locked := false
var dir_released := true
var arrows: Array[MeshInstance3D] = []
var arrow_opts: Array = []
var near_door: Dictionary = {}
var near_phone := false
var use_pad := false
var aid_on := false

var bell: AudioStreamPlayer3D
var bell_tail: AudioStreamPlayer
var bell_wall: AudioStreamPlayer3D
var wall_db := -60.0
var srv: AudioEffectReverb
var amb_duck := 1.0
var idle_t := 0.0
var amb: AudioStreamPlayer
var amb_extra: Array = []
var loops: Array = []
var bell_db := -30.0
var bell_cut := 800.0
var bell_wet := 0.3
var bell_src := Vector3.ZERO
var bell_stopped := false
var field_timer := 0.0
var lp: AudioEffectLowPassFilter
var rv: AudioEffectReverb
var amb_gain := 1.0
var streams: Dictionary = {}
var step_surface := "concrete"

var bot := false
var bot_vec := Vector3.ZERO
var bot_fail := ""
var shot_dir := ""
var pause_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_setup_audio()
	var args0 := OS.get_cmdline_user_args()
	if not booted:
		booted = true
		for a: String in args0:
			if a == "--lab":
				lab_menu = true
			elif a.begins_with("--lab="):
				lab_menu = true
				lab_file = a.substr(6)
			elif a == "--marathon":
				Story.marathon = true
				Story.no_save = true
			elif a in ["--autoplay", "--monkey", "--tour", "--labbot", "--camaudit"]:
				Story.no_save = true
			elif a.begins_with("--chapter="):
				Story.chapter = clampi(int(a.substr(10)), 1, Story.CHAPTERS.size())
				Story.resume = Story.chapter > 1
	lab = lab_file != ""
	var level_path := ("res://level/lab/%s.txt" % lab_file) if lab else Story.level_path()
	L = LevelLogic.new()
	L.load_file(level_path)
	if not lab and Story.chapter > 1:
		meta = LevelMeta.load_file(level_path)
		ring_period = meta.period
		ring_len = meta.on
		src_db = meta.source_db
		wall_gain = meta.wall_db
		line_period = meta.line_period
		line_len = meta.line_on
	story = Story.new()
	story.m = self
	add_child(story)
	_setup_view()
	_setup_world()
	story.setup_world()
	_setup_sound_sources()
	var args := OS.get_cmdline_user_args()
	shot_dir = ProjectSettings.globalize_path("res://build/shots")
	if OS.has_feature("template"):
		shot_dir = OS.get_executable_path().get_base_dir().path_join("shots")
	if lab:
		_enter_lab()
	elif lab_menu:
		_enter_lab_menu()
	elif Story.resume:
		story.enter_chapter()
	else:
		_enter_title()
	for a: String in args:
		if a.begins_with("--aid="):
			aid_mode = clampi(int(a.substr(6)), 0, 2)
			aid_on = aid_mode > 0
			hud.aid_strong = aid_mode == 2
	if lab and "--labbot" in args:
		bot = true
		_bot_lab.call_deferred()
	elif lab or lab_menu:
		pass
	elif "--autoplay" in args or Story.marathon:
		bot = true
		_bot_autoplay.call_deferred()
	elif "--monkey" in args:
		bot = true
		_bot_monkey.call_deferred()
	elif "--tour" in args:
		bot = true
		_bot_tour.call_deferred()
	elif "--camaudit" in args:
		story.audit()
		get_tree().quit(0)


# ------------------------------------------------------------------ setup
func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_LEFT, KEY_A], "move_right": [KEY_RIGHT, KEY_D],
		"move_up": [KEY_UP, KEY_W], "move_down": [KEY_DOWN, KEY_S],
		"act": [KEY_Z, KEY_SPACE, KEY_ENTER], "back": [KEY_X, KEY_BACKSPACE],
		"aid": [KEY_C], "pause": [KEY_ESCAPE], "full": [KEY_F11], "quit": [KEY_Q],
	}
	var pads := {
		"move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT,
		"move_up": JOY_BUTTON_DPAD_UP, "move_down": JOY_BUTTON_DPAD_DOWN,
		"act": JOY_BUTTON_A, "back": JOY_BUTTON_B, "aid": JOY_BUTTON_Y, "pause": JOY_BUTTON_START,
	}
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0], "move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
	for a: String in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.35)
		for k: int in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
		if pads.has(a):
			var jb := InputEventJoypadButton.new()
			jb.button_index = pads[a]
			InputMap.action_add_event(a, jb)
		if axes.has(a):
			var jm := InputEventJoypadMotion.new()
			jm.axis = axes[a][0]
			jm.axis_value = axes[a][1]
			InputMap.action_add_event(a, jm)

func _setup_audio() -> void:
	for nm: String in ["Bell", "Wall", "Sfx", "Amb"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, nm)
		AudioServer.set_bus_send(i, "Master")
	lp = AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 900.0
	lp.resonance = 0.4
	rv = AudioEffectReverb.new()
	rv.room_size = 0.78
	rv.damping = 0.35
	rv.spread = 0.9
	rv.predelay_msec = 40.0
	rv.dry = 1.0
	rv.wet = 0.3
	var bi := AudioServer.get_bus_index("Bell")
	AudioServer.add_bus_effect(bi, lp)
	AudioServer.add_bus_effect(bi, rv)
	srv = AudioEffectReverb.new()
	srv.room_size = 0.5
	srv.damping = 0.5
	srv.dry = 1.0
	srv.wet = 0.16
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Sfx"), srv)
	for f: String in ["bell_ring", "bell_tail", "rattle", "knob_insert", "knob_remove", "knob_turn", "thud", "door_move", "door_seat", "receiver_lift", "room_tone", "fluoro_buzz", "clock_tick", "vending_hum", "ui_start", "knob_ting", "bell_wall", "door_squeak", "line_next", "line_cut"]:
		streams[f] = load("res://assets/audio/%s.wav" % f)
	for f: String in ["bell_ring", "bell_wall", "room_tone", "fluoro_buzz", "clock_tick", "vending_hum"]:
		var w: AudioStreamWAV = streams[f]
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	for f: String in EXTRA_SOUNDS:
		if ResourceLoader.exists("res://assets/audio/%s.wav" % f):
			streams[f] = load("res://assets/audio/%s.wav" % f)
			if f.ends_with("_ring") or f.ends_with("_wall") or f.ends_with("_pipe") or f.ends_with("_loop") or f.ends_with("_hum"):
				var w2: AudioStreamWAV = streams[f]
				w2.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w2.loop_begin = 0
				w2.loop_end = int(w2.get_length() * w2.mix_rate)
	for f: String in ["cloth1", "cloth2", "cloth3", "creak1", "creak2", "creak3"]:
		streams[f] = load("res://assets/audio/%s.ogg" % f)
	for surf: String in ["wood", "carpet", "concrete"]:
		for i in 5:
			streams["step_%s_%d" % [surf, i]] = load("res://assets/audio/footstep_%s_00%d.ogg" % [surf, i])

func _setup_view() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(VW, VH)
	vp.own_world_3d = true
	vp.audio_listener_enable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(vp)
	screen = TextureRect.new()
	screen.texture = vp.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	screen.position = Vector2.ZERO
	screen.size = Vector2(1024, 768)
	post = ShaderMaterial.new()
	post.shader = load("res://shaders/post.gdshader")
	screen.material = post
	add_child(screen)
	pause_label = Label.new()
	pause_label.text = "PAUSE\n\nEsc  つづける\nQ  おわる"
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_label.size = Vector2(1024, 768)
	var ff: FontFile = load("res://assets/font/DotGothic16-Regular.ttf")
	pause_label.add_theme_font_override("font", ff)
	pause_label.add_theme_font_size_override("font_size", 32)
	pause_label.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(1024, 768)
	dim.show_behind_parent = true
	pause_label.add_child(dim)
	add_child(pause_label)

func _setup_world() -> void:
	world = Node3D.new()
	vp.add_child(world)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.014, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.5)
	env.ambient_light_energy = 0.42
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.055, 0.05)
	env.fog_density = 0.028
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	world.add_child(we)
	B = Building.new()
	world.add_child(B)
	B.bare = lab
	B.meta = meta
	B.build(L)
	B.build_exterior(EXT)
	for i in L.doors.size():
		var d := Door.new()
		B.add_child(d)
		d.setup(i, L.doors[i], B)
		doors.append(d)
	player = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.27
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	player.add_child(cs)
	human = Human.new()
	player.add_child(human)
	human.footstep.connect(_on_footstep)
	world.add_child(player)
	player.position = Building.cell_center(L.start_cell) + (Vector3.ZERO if lab or meta != null else Vector3(0, 0, -0.9))
	title_human = Human.new()
	world.add_child(title_human)
	title_human.position = EXT + Vector3(0.9, 0, 3.0)
	title_human.set_layers(1 << 18)
	title_human.has_look = true
	title_human.look_target = EXT + Vector3(4.0, 10.8, -6.0)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 90.0
	world.add_child(cam)
	cam.make_current()
	listener = AudioListener3D.new()
	world.add_child(listener)
	listener.make_current()
	for i in 2:
		var a := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.62, 0.62)
		q.orientation = PlaneMesh.FACE_Y
		a.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = load("res://assets/tex/arrow.png")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
		m.render_priority = 5
		a.material_override = m
		a.visible = false
		world.add_child(a)
		arrows.append(a)
	hud = Hud.new()
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	layer.add_child(hud)
	field = SoundField.new()
	var src := B.phone_pos + Vector3(0, 0.7, 0)
	if meta != null and meta.source != Vector3.INF:
		src = meta.source
	field.setup(L, B, doors, src, B.duct_pairs)
	field.update()

## the chapter's own bell if it has one, the first telephone's otherwise
func _snd(part: String) -> String:
	if meta != null and streams.has("%s_%s" % [meta.bell, part]):
		return "%s_%s" % [meta.bell, part]
	return "bell_" + part

func _setup_sound_sources() -> void:
	bell = AudioStreamPlayer3D.new()
	bell.stream = streams[_snd("ring")]
	bell.bus = "Bell"
	bell.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	bell.panning_strength = 1.4
	bell.max_polyphony = 1
	world.add_child(bell)
	# the second voice of the same bell: what comes straight through the walls. it always points at
	# the real telephone, however the doors stand, and it never gets clear.
	bell_wall = AudioStreamPlayer3D.new()
	bell_wall.stream = streams[_snd("wall")]
	bell_wall.bus = "Wall"
	bell_wall.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	bell_wall.panning_strength = 1.2
	bell_wall.volume_db = -60.0
	world.add_child(bell_wall)
	if meta != null and streams.has(meta.bell + "_pipe"):
		# the same ring as it leaves the mouth of a duct. locked to the bell, crossfaded with it.
		bell_pipe = AudioStreamPlayer3D.new()
		bell_pipe.stream = streams[meta.bell + "_pipe"]
		bell_pipe.bus = "Bell"
		bell_pipe.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		bell_pipe.panning_strength = 1.4
		bell_pipe.volume_db = -60.0
		world.add_child(bell_pipe)
		bell_pipe.play()
	bell.play()
	bell_wall.play()
	bell_tail = AudioStreamPlayer.new()
	bell_tail.stream = streams[_snd("tail")]
	bell_tail.bus = "Bell"
	add_child(bell_tail)
	line = AudioStreamPlayer.new()
	line.stream = streams[meta.line] if meta != null and streams.has(meta.line) else streams["line_next"]
	if streams.has("line_a%d" % Story.chapter):
		line.stream = streams["line_a%d" % Story.chapter]   # the same line, with this chapter's digit dialled on it
	line.volume_db = -15.0
	add_child(line)
	amb = AudioStreamPlayer.new()
	amb.stream = streams["room_tone"]
	amb.bus = "Amb"
	amb.volume_db = -22.0
	add_child(amb)
	amb.play()
	if meta != null:
		for a: Array in meta.ambs:
			if streams.has(a[0]):
				var ap := AudioStreamPlayer.new()
				ap.stream = streams[a[0]]
				ap.bus = "Amb"
				ap.volume_db = a[1]
				ap.set_meta("base", a[1])
				add_child(ap)
				ap.play()
				amb_extra.append(ap)
	if lab or meta != null:
		return
	for src: Array in [["clock_tick", B.clock_pos, -9.0, 1.6, 11.0], ["vending_hum", B.vending_pos, -15.0, 1.2, 8.0], ["fluoro_buzz", Vector3(1.5, 2.6, 13.0), -17.0, 1.2, 7.0]]:
		var p := AudioStreamPlayer3D.new()
		p.stream = streams[src[0]]
		p.bus = "Amb"
		p.volume_db = src[2]
		p.unit_size = src[3]
		p.max_distance = src[4]
		p.position = src[1]
		p.set_meta("base", src[2])
		world.add_child(p)
		p.play()
		loops.append(p)

func _restart() -> void:
	get_tree().paused = false
	AudioServer.set_bus_mute(0, false)
	for nm: String in ["Bell", "Wall", "Sfx", "Amb"]:
		AudioServer.remove_bus(AudioServer.get_bus_index(nm))
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ DOOOOOR LAB
func _enter_lab_menu() -> void:
	state = St.LABMENU
	hud.mode = "lab"
	hud.fade = 0.0
	cam_override = true
	_lab_rows()

func _lab_rows() -> void:
	var rows := []
	for e: Array in LAB:
		var r: Dictionary = lab_results.get(e[0], {})
		var txt := "まだ"
		if not r.is_empty():
			txt = "%d回転  %s   最少 %d回転   （最短解は %d回転）  %d回目" % [r.turns, _clock(r.time), r.best, r.min, r.tries]
		rows.append([e[1], txt])
	hud.lab_rows = rows
	hud.lab_sel = lab_sel

func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]

func _enter_lab() -> void:
	state = St.PLAY
	hud.mode = "play"
	hud.fade = 1.0
	create_tween().tween_property(hud, "fade", 0.0, 0.8)
	intro_done = true
	first_attach_done = true
	phone_seen = true
	hud.knob_known = true
	title_human.visible = false
	cam_override = false
	env.fog_density = 0.005
	# one camera for the whole board, high behind the south wall: a doll's house
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c: Vector2i in L.cells:
		lo = lo.min(Vector2(c))
		hi = hi.max(Vector2(c) + Vector2.ONE)
	lo *= Building.CELL
	hi *= Building.CELL
	var d := hi.y - lo.y
	var m := maxf(hi.x - lo.x, d)
	lab_cfg = [Vector3((lo.x + hi.x) * 0.5, 3.0 + 0.72 * m, hi.y + 1.2 + 0.22 * d), Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5 - 0.3), 0.0, 50.0]
	lab_min = Solver.search(L, L.start_cell).rot
	for e: Array in LAB:
		if e[0] == lab_file:
			hud.lab_title = e[1]
	if hud.lab_title == "":
		hud.lab_title = lab_file
	cam_room = ""
	_update_room(true)

func _lab_finish() -> void:
	state = St.BUSY
	hud.prompt_act = false
	hud.prompt_back = false
	human.pose = "reach"
	await wait(0.5)
	sfx("receiver_lift", 0.0)
	bell_stopped = true
	bell_tail.volume_db = bell_db - 2.0
	bell_tail.play()
	bell.stop()
	bell_wall.stop()
	B.phone_handset.visible = false
	human.show_handset(true)
	human.pose = "phone"
	var prev: Dictionary = lab_results.get(lab_file, {})
	lab_results[lab_file] = {"turns": lab_turns, "time": lab_t, "min": lab_min, "tries": int(prev.get("tries", 0)) + 1, "best": mini(int(prev.get("best", 999)), lab_turns)}
	var line := "%s  %s  turns=%d  time=%s  shortest=%d  moves=%s" % [Time.get_datetime_string_from_system(), lab_file, lab_turns, _clock(lab_t), lab_min, " ".join(lab_log)]
	print("LAB ", line)
	var path := shot_dir.get_base_dir().path_join("lab_log.txt")
	DirAccess.make_dir_recursive_absolute(shot_dir.get_base_dir())
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(line)
		f.close()
	hud.lab_done = "できた    %d回転    %s" % [lab_turns, _clock(lab_t)]
	hud.lab_done2 = "最短解は %d回転" % lab_min
	await wait(1.0)
	state = St.LABDONE


func sfx(nm: String, db := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = streams[nm]
	p.bus = "Sfx"
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout


# ------------------------------------------------------------------ flow
func _enter_title() -> void:
	state = St.TITLE
	hud.mode = "title"
	hud.cont = Story.saved()
	hud.title_alpha = 0.0
	hud.fade = 1.0
	cam_override = true
	env.fog_density = 0.02
	env.background_color = Color(0.02, 0.03, 0.06)
	var tw := create_tween()
	tw.tween_property(hud, "fade", 0.0, 2.5)
	tw.tween_property(hud, "title_alpha", 1.0, 1.5)

func _start_game() -> void:
	if state != St.TITLE:
		return
	state = St.TRANSITION
	Story.heard = [false, false, false]
	Story.save(1)
	sfx("ui_start", -6.0)
	var tw := create_tween()
	tw.tween_property(hud, "title_alpha", 0.0, 0.5)
	tw.parallel().tween_property(hud, "fade", 1.0, 1.6)
	await tw.finished
	await wait(0.7)
	hud.mode = "play"
	env.fog_density = 0.028
	env.background_color = Color(0.012, 0.014, 0.02)
	title_human.visible = false
	cam_override = false
	cam_room = ""
	_update_room(true)
	var tw2 := create_tween()
	tw2.tween_property(hud, "fade", 0.0, 2.2)
	await wait(0.9)
	state = St.PLAY

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
		if not (ev is InputEventJoypadMotion and absf(ev.axis_value) < 0.5):
			use_pad = true
	elif ev is InputEventKey:
		use_pad = false
	if ev.is_action_pressed("full") or (ev is InputEventKey and ev.pressed and ev.keycode == KEY_ENTER and ev.alt_pressed):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_L and (state == St.TITLE or (lab and (state == St.PLAY or state == St.LABDONE))):
			lab_menu = true
			lab_file = ""
			_restart()
			return
		if ev.physical_keycode == KEY_R and lab and (state == St.PLAY or state == St.DOOR or state == St.LABDONE):
			_restart()
			return
	if state == St.LABMENU:
		if ev.is_action_pressed("move_up"):
			lab_sel = (lab_sel + LAB.size() - 1) % LAB.size()
		elif ev.is_action_pressed("move_down"):
			lab_sel = (lab_sel + 1) % LAB.size()
		elif ev.is_action_pressed("act"):
			lab_file = LAB[lab_sel][0]
			_restart()
		elif ev.is_action_pressed("back") or ev.is_action_pressed("pause"):
			lab_menu = false
			lab_file = ""
			_restart()
		hud.lab_sel = lab_sel
		return
	if ev.is_action_pressed("pause"):
		if state == St.TITLE:
			if ev is InputEventJoypadButton:
				_on_act()
			elif OS.get_name() != "Web":
				get_tree().quit()
		else:
			get_tree().paused = not get_tree().paused
			pause_label.visible = get_tree().paused
			# the only place the number is written down: what has been heard so far
			pause_label.text = "PAUSE\n\nEsc  つづける\nQ  おわる" + ("\n\n\n" + Story.memo() if Story.heard.has(true) else "")
			AudioServer.set_bus_mute(0, get_tree().paused)
		return
	if get_tree().paused:
		if ev.is_action_pressed("quit") and OS.get_name() != "Web":
			get_tree().quit()
		return
	if ev.is_action_pressed("aid"):
		aid_mode = (aid_mode + 1) % 3
		aid_on = aid_mode > 0
		hud.aid_strong = aid_mode == 2
		hud.aid_note = 1.8
	if ev.is_action_pressed("act"):
		_on_act()
	elif ev.is_action_pressed("back"):
		_on_back()

func _on_act() -> void:
	if story.dialing:
		story.dial_press()
		return
	match state:
		St.TITLE:
			if hud.title_alpha > 0.5:
				_start_game()
		St.END:
			_restart()
		St.LABDONE:
			lab_menu = true
			lab_file = ""
			_restart()
		St.DOOR:
			_leave_door(false)
		St.PLAY:
			if near_phone:
				if lab:
					_lab_finish()
				elif not story.on_phone():
					_ending()
			elif not near_door.is_empty():
				var d: Door = near_door.door
				if not near_door.socket:
					_blank_side(d)
				elif not intro_done:
					_intro(d)
				elif L.knob_on == -1:
					_attach(d)
				elif L.knob_on == d.index:
					_grab(d)
				else:
					_no_knob(d)

func _on_back() -> void:
	if state == St.TITLE:
		if hud.cont > 1 and hud.title_alpha > 0.5:
			Story.chapter = hud.cont
			Story.resume = true
			_restart()
		return
	if story.dialing:
		story.dial_erase()
		return
	if story.on_back():
		return
	if state == St.DOOR:
		_leave_door(true)
	elif state == St.PLAY and not near_door.is_empty() and near_door.socket and L.knob_on == near_door.door.index:
		_take_knob(near_door.door)

func _align(d: Door, socket := true, dur := 0.28) -> void:
	var target := d.rider_world(socket)
	var yaw := d.rider_yaw(socket)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(player, "global_position", target, dur)
	tw.tween_method(func(t: float) -> void: player.rotation.y = lerp_angle(player.rotation.y, yaw, t), 0.0, 1.0, dur)
	human.pose = "walk"
	human.walk_speed = 1.2
	await tw.finished
	human.walk_speed = 0.0
	player.rotation.y = yaw

func _hole_cam(d: Door, fov := 44.0) -> void:
	var hole := d.hole_world()
	var nrm := d.socket_normal()
	var along := (d.pivot.global_transform.basis * Vector3(1, 0, 0)).normalized()
	cam_override = true
	cam.global_position = hole + nrm * 0.42 - along * 0.6 + Vector3(0, 0.16, 0)
	cam.look_at(hole + Vector3(0, -0.02, 0))
	cam.fov = fov

func _intro(d: Door) -> void:
	# the first thirty seconds: a hand finds no knob. a pocket remembers one.
	state = St.BUSY
	await _align(d)
	human.pose = "reach"
	await wait(0.45)
	sfx("rattle", -2.0)
	_hole_cam(d)
	cam_shake = 0.012
	await wait(0.5)
	cam_shake = 0.012
	await wait(1.4)
	human.pose = "idle"
	await wait(0.5)
	human.pose = "pocket"
	human.has_look = false
	var nrm := d.socket_normal()
	var along := (d.pivot.global_transform.basis * Vector3(1, 0, 0)).normalized()
	var pp := player.global_position
	cam.global_position = pp + along * 1.45 + nrm * 0.55 + Vector3(0, 1.3, 0)
	cam.look_at(pp + Vector3(0, 1.18, 0) - nrm * 0.15)
	cam.fov = 42.0
	sfx("cloth2", -8.0)
	await wait(0.9)
	human.show_knob(true)
	sfx("knob_ting", -4.0)
	await wait(0.35)
	var hand := human.right_hand_global()
	cam.global_position = hand + along * 0.5 + nrm * 0.3 + Vector3(0, 0.2, 0)
	cam.look_at(hand + Vector3(0, 0.03, 0))
	cam.fov = 34.0
	await wait(1.9)
	intro_done = true
	hud.knob_known = true
	hud.knob_flash = 1.6
	human.pose = "idle"
	human.show_knob(false)
	cam_override = false
	_update_room(true)
	await wait(0.3)
	state = St.PLAY

func _attach(d: Door) -> void:
	state = St.BUSY
	await _align(d)
	human.show_knob(true)
	human.pose = "reach"
	if not first_attach_done:
		_hole_cam(d, 30.0)
		await wait(0.9)
	else:
		await wait(0.35)
	sfx("knob_insert", -1.0)
	await wait(0.26)
	human.show_knob(false)
	d.set_knob(true)
	L.knob_on = d.index
	cam_shake = 0.008
	await wait(0.75 if not first_attach_done else 0.35)
	first_attach_done = true
	_enter_door(d)

func _grab(d: Door) -> void:
	state = St.BUSY
	await _align(d)
	_enter_door(d)

func _enter_door(d: Door) -> void:
	cur_door = d
	human.pose = "hold"
	human.has_look = false
	cam_override = true
	var h := d.global_position
	cam.global_position = h + Vector3(0, 8.4, 2.3)
	cam.look_at(h + Vector3(0, 0, -0.25), Vector3(0, 0, -1))
	cam.fov = 52.0
	_refresh_arrows()
	dir_released = false
	state = St.DOOR

func _refresh_arrows() -> void:
	arrow_opts.clear()
	for a in arrows:
		a.visible = false
	if cur_door == null:
		return
	var here := player.global_position
	var i := 0
	for r: Array in L.rotations(cur_door.index):
		var dest := cur_door.rider_world_at(r[0])
		var mid := cur_door.global_position + Basis(Vector3.UP, (cur_door.def.pos + r[1] * 0.5) * PI * 0.5) * cur_door.rider_local(true) * 1.12
		var dirv := (dest - here).normalized()
		arrow_opts.append({"pos": r[0], "turn": r[1], "dir": dirv})
		var a := arrows[i]
		a.global_position = Vector3(mid.x, 0.06, mid.z)
		a.rotation.y = atan2(-dirv.x, -dirv.z)
		a.visible = true
		i += 1

func _door_choose(opt: Dictionary) -> void:
	if state != St.DOOR:
		return
	state = St.BUSY
	var d := cur_door
	for a in arrows:
		a.visible = false
	lab_turns += 1
	lab_log.append("%d%s" % [d.def.id, LevelLogic.DIRNAME[opt.pos]])
	sfx("knob_turn", -3.0)
	await wait(0.32)
	sfx("door_move", -1.0, randf_range(0.94, 1.04))
	sfx("door_squeak", -17.0, randf_range(0.8, 1.0))
	sfx("creak%d" % randi_range(1, 3), -12.0, 0.7)
	var strain := "push" if L.is_push(d.index, opt.turn) else "pull"
	d.turn(opt.pos, opt.turn, 2.35)
	while d.turning:
		player.global_position = d.rider_world(true)
		player.rotation.y = d.rider_yaw(true)
		human.pose = strain
		field.update()
		await get_tree().process_frame
	player.global_position = d.rider_world(true)
	human.pose = "hold"
	sfx("door_seat", 0.0)
	cam_shake = 0.05
	field.update()
	_update_layers()
	# one held breath after the leaf lands: the building goes quiet and only the changed bell is left
	amb_duck = 0.3
	create_tween().tween_property(self, "amb_duck", 1.0, 2.6).set_delay(0.5)
	await wait(0.85)
	_refresh_arrows()
	dir_released = false
	state = St.DOOR

func _leave_door(take: bool) -> void:
	state = St.BUSY
	var d := cur_door
	for a in arrows:
		a.visible = false
	if take:
		human.pose = "reach"
		sfx("knob_remove", -2.0)
		await wait(0.3)
		d.set_knob(false)
		L.knob_on = -1
		human.show_knob(true)
		hud.knob_flash = 0.6
		await wait(0.45)
		human.show_knob(false)
	cur_door = null
	human.pose = "idle"
	cam_override = false
	_update_room(true)
	await wait(0.15)
	state = St.PLAY

func _take_knob(d: Door) -> void:
	state = St.BUSY
	await _align(d)
	human.pose = "reach"
	await wait(0.25)
	sfx("knob_remove", -2.0)
	await wait(0.3)
	d.set_knob(false)
	L.knob_on = -1
	human.show_knob(true)
	hud.knob_flash = 0.6
	await wait(0.45)
	human.show_knob(false)
	human.pose = "idle"
	state = St.PLAY

func _blank_side(d: Door) -> void:
	state = St.BUSY
	await _align(d, false)
	human.pose = "thud"
	await wait(0.3)
	sfx("thud", -3.0)
	cam_shake = 0.02
	await wait(0.7)
	human.pose = "idle"
	await wait(0.2)
	state = St.PLAY

func _no_knob(d: Door) -> void:
	# the knob is sitting in some other door
	state = St.BUSY
	await _align(d)
	human.pose = "reach"
	await wait(0.35)
	sfx("rattle", -4.0)
	cam_shake = 0.012
	await wait(0.8)
	human.pose = "pat"
	sfx("cloth1", -8.0)
	hud.knob_blink = 1.6
	await wait(1.1)
	human.pose = "idle"
	state = St.PLAY

func _ending() -> void:
	state = St.ENDING
	hud.mode = "none"
	hud.prompt_act = false
	hud.prompt_back = false
	var stand := B.phone_pos + Vector3(0.0, 0, 0.66)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(player, "global_position", stand, 0.6)
	tw.tween_method(func(t: float) -> void: player.rotation.y = lerp_angle(player.rotation.y, 0.0, t), 0.0, 1.0, 0.6)
	human.pose = "walk"
	human.walk_speed = 1.0
	await tw.finished
	human.walk_speed = 0.0
	human.pose = "idle"
	human.has_look = true
	human.look_target = B.phone_pos + Vector3(0, 0.7, 0)
	cam_override = true
	# from the side: the telephone on one half of the frame, the hand coming in from the other
	cam.global_position = B.phone_pos + Vector3(1.3, 1.02, 0.3)
	cam.look_at(B.phone_pos + Vector3(0.0, 0.84, 0.3))
	cam.fov = 42.0
	# let it ring once more, close.
	await wait(2.4)
	human.pose = "reach"
	await wait(0.7)
	sfx("receiver_lift", 0.0)
	bell_stopped = true
	if fmod(bell.get_playback_position(), ring_period) < ring_len + 0.25:
		bell_tail.volume_db = bell_db - 2.0
		bell_tail.play()
	bell.stop()
	bell_wall.stop()
	if bell_pipe != null:
		bell_pipe.stop()
	B.phone_handset.visible = false
	human.show_handset(true)
	human.pose = "phone"
	human.has_look = false
	await wait(2.6)
	cam.global_position = B.phone_pos + Vector3(-1.25, 1.5, -0.2)
	cam.look_at(stand + Vector3(0, 1.5, 0))
	cam.fov = 36.0
	var tw2 := create_tween()
	tw2.tween_property(self, "amb_gain", 0.0, 5.5)
	# the line is open. somebody dials. somewhere else, another bell.
	await wait(0.8)
	line.play()
	await wait(7.7)
	# the building, from above, exactly as the player left it.
	env.fog_density = 0.0
	var plan := story.plan_cam()
	cam.global_position = plan[0]
	cam.look_at(plan[1], Vector3(0, 0, -1))
	cam.fov = plan[2]
	await wait(8.0)
	var tw3 := create_tween()
	tw3.tween_property(hud, "fade", 1.0, 3.0)
	await tw3.finished
	# it is still ringing in the dark; then the line is cut in the middle of a ring
	await wait(2.5)
	line.stop()
	sfx("line_cut", -8.0)
	await wait(1.6)
	# not an ending: the next building is already ringing
	story.advance()
	return
	hud.mode = "end"
	var tw4 := create_tween()
	tw4.tween_property(hud, "end_alpha", 1.0, 2.5)
	await tw4.finished
	await wait(1.5)
	state = St.END


# ------------------------------------------------------------------ per-frame
func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if state != St.PLAY:
		player.velocity = Vector3.ZERO
		return
	var dir := Vector3.ZERO
	if bot:
		dir = bot_vec
	else:
		var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if iv.length() < 0.2:
			move_locked = false
		else:
			if not move_locked:
				move_basis = cam.global_transform.basis
				move_locked = true
			var f := -move_basis.z
			f.y = 0
			if f.length() < 0.2:
				f = move_basis.y
				f.y = 0
			f = f.normalized()
			var r := Vector3(-f.z, 0, f.x)
			dir = r * iv.x - f * iv.y
			if dir.length() > 1.0:
				dir = dir.normalized()
	player.velocity = dir * SPEED
	player.move_and_slide()
	player.global_position.y = 0.0
	var sp := player.get_real_velocity().length()
	idle_t = 0.0 if dir.length() > 0.1 else idle_t + delta
	if dir.length() > 0.1:
		var yaw := atan2(-dir.x, -dir.z)
		player.rotation.y = lerp_angle(player.rotation.y, yaw, minf(1.0, delta * 9.0))
		human.pose = "walk"
		human.walk_speed = maxf(sp, 0.6)
	else:
		human.pose = "idle"
		human.walk_speed = 0.0

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	clock += delta
	post.set_shader_parameter("time_s", clock)
	_update_flicker(delta)
	if lab and state != St.LABDONE:
		lab_t += delta
		hud.lab_text = "%s    %d回転    %s" % [hud.lab_title, lab_turns, _clock(lab_t)]
	if state == St.TITLE or state == St.LABMENU or state == St.TRANSITION and hud.mode == "title":
		_title_camera()
	else:
		_update_room(false)
		_update_camera(delta)
	if state == St.PLAY:
		_scan_interactions()
	else:
		hud.prompt_act = false
		hud.prompt_back = state == St.DOOR
		if state == St.DOOR:
			hud.prompt_act = true
			_door_input()
	_update_sound(delta)
	hud.use_pad = use_pad
	hud.knob_in_hand = L.knob_on == -1 and not story.knob_gone
	hud.aid_on = aid_on

func _title_camera() -> void:
	var t := clock
	cam.fov = 50.0
	cam.global_position = EXT + Vector3(2.9 + sin(t * 0.07) * 0.5, 1.05 + sin(t * 0.11) * 0.06, 7.2 - minf(t * 0.03, 1.4))
	cam.look_at(EXT + Vector3(0.6, 4.4, -6.0))
	listener.global_transform = cam.global_transform

func _cam_cfg() -> Array:
	if lab:
		return lab_cfg
	return story.view_for(player.global_position)

func _update_room(force: bool) -> void:
	var room := B.room_of(player.global_position)
	if room == "":
		return
	var cell := Building.world_to_cell(player.global_position)
	if not lab and not cam_override:
		story.view_for(player.global_position)   # decides whether the player has been lost by the usual camera
	var key := story.key_of(cell) if not lab else NO_CELL
	if room == cam_room and key == cam_cell and not force:
		return
	if room != cam_room:
		cam_room = room
		_update_layers()
		step_surface = B.styles[room].step
		if step_surface == "tile":
			step_surface = "concrete"
	cam_cell = key
	if cam_override:
		return
	var cfg := _cam_cfg()
	cam.global_position = cfg[0]
	cam.fov = cfg[3]
	cam_look = _look_goal(cfg)
	cam.look_at(cam_look)
	if meta == null and not lab and cell == Vector2i(2, 2) and not phone_seen and state == St.PLAY:
		_discover()
	elif meta != null and not phone_seen and state == St.PLAY and story.sees_phone(cell):
		story.discover()

## the first time the telephone comes into view: stop, and let it be looked at.
func _discover() -> void:
	phone_seen = true
	state = St.BUSY
	hud.mode = "none"
	human.pose = "idle"
	human.walk_speed = 0.0
	human.has_look = true
	human.look_target = B.phone_pos + Vector3(0, 0.7, 0)
	cam_override = true
	var cfg: Array = DISCOVER_CAM
	cam.global_position = cfg[0]
	cam.look_at(cfg[1])
	cam.fov = 50.0
	create_tween().tween_property(cam, "fov", 38.0, 2.8).set_trans(Tween.TRANS_SINE)
	if bot:
		await wait(1.6)
		await _shot("29_discovery")
		await wait(1.2)
	else:
		await wait(2.9)
	cam_override = false
	hud.mode = "play"
	_update_room(true)
	state = St.PLAY

func _update_layers() -> void:
	var room := B.room_of(player.global_position)
	if room != "":
		human.set_layers(B.room_bit[room])

func _look_goal(cfg: Array) -> Vector3:
	var base: Vector3 = cfg[1]
	return base.lerp(player.global_position + Vector3(0, 1.0, 0), cfg[2])

func _update_camera(delta: float) -> void:
	if not cam_override and cam_room != "":
		var cfg := _cam_cfg()
		cam_look = cam_look.lerp(_look_goal(cfg), minf(1.0, delta * 3.0))
		cam.global_position = cfg[0]
		cam.look_at(cam_look)
	if cam_shake > 0.0005:
		cam.h_offset = randf_range(-1, 1) * cam_shake
		cam.v_offset = randf_range(-1, 1) * cam_shake
		cam_shake = lerpf(cam_shake, 0.0, minf(1.0, delta * 9.0))
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
	# ears: at the player's head, turned like the camera so that left on screen is left in the speakers
	var yaw := cam.global_rotation.y
	if state == St.DOOR or (cam_override and absf(cam.global_transform.basis.z.y) > 0.9):
		yaw = 0.0
	listener.global_position = player.global_position + Vector3(0, 1.55, 0)
	listener.rotation = Vector3(0, lerp_angle(listener.rotation.y, yaw, minf(1.0, delta * 3.0)), 0)

func _scan_interactions() -> void:
	near_door = {}
	var p := player.global_position
	var pc := Building.world_to_cell(p)
	var bd := 1.0
	for d in doors:
		for s: bool in [true, false]:
			var r := d.rider_world(s)
			if Building.world_to_cell(r) != pc:
				continue
			var dist := Vector2(p.x - r.x, p.z - r.z).length()
			if dist < bd:
				bd = dist
				near_door = {"door": d, "socket": s}
	var ph := B.phone_pos
	near_phone = pc == L.phone_cell and Vector2(p.x - ph.x, p.z - ph.z - 0.5).length() < 1.0 and story.phone_usable()
	hud.prompt_act = near_phone or not near_door.is_empty()
	hud.prompt_back = not near_door.is_empty() and near_door.socket and L.knob_on == near_door.door.index
	story.scan(pc, p)
	human.has_look = hud.prompt_act
	if not hud.prompt_act and idle_t > 1.1 and not bell_stopped:
		# standing still, the head drifts toward wherever the ringing is coming from
		human.has_look = true
		human.look_target = Vector3(bell_src.x, 1.5, bell_src.z)
	if near_phone:
		human.look_target = ph + Vector3(0, 0.7, 0)
	elif not near_door.is_empty():
		var d: Door = near_door.door
		human.look_target = d.hole_world()

func _door_input() -> void:
	if bot:
		return
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if iv.length() < 0.3:
		dir_released = true
		return
	if not dir_released or iv.length() < 0.7:
		return
	# overhead camera: screen right = +x, screen up = -z
	var want := Vector3(iv.x, 0, iv.y).normalized()
	var best := {}
	var bs := 0.35
	for o: Dictionary in arrow_opts:
		var s: float = want.dot(o.dir)
		if s > bs:
			bs = s
			best = o
	if not best.is_empty():
		dir_released = false
		_door_choose(best)

func _update_flicker(delta: float) -> void:
	for l: OmniLight3D in B.flicker_lights:
		var base: float = l.get_meta("base")
		var n := sin(clock * 37.0) * sin(clock * 5.3 + 1.0) * sin(clock * 0.9)
		var k := 1.0
		if n > 0.55:
			k = 0.25 + 0.3 * randf()
		elif fmod(clock, 7.3) < 0.08:
			k = 0.4
		l.light_energy = base * k
		var tube: MeshInstance3D = l.get_meta("tube")
		(tube.material_override as StandardMaterial3D).albedo_color = Color(0.92, 1.0, 0.94) * (0.35 + 0.65 * k)

func _update_sound(delta: float) -> void:
	field_timer -= delta
	if field_timer <= 0.0:
		field_timer = 0.12
		field.update()
	var ring_on := not bell_stopped and fmod(bell.get_playback_position(), ring_period) < ring_len
	hud.ring_env = 1.0 if ring_on else 0.0
	# the handset rattles in its cradle exactly while the clapper runs
	B.phone_handset.rotation.z = sin(clock * 83.0) * 0.045 if ring_on and not story.is_final() else 0.0
	var lpos_ := line.get_playback_position() if line.playing else -1.0
	story.line_tick(lpos_)
	hud.echo_env = 1.0 if lpos_ >= 5.8 and fmod(lpos_ - 5.8, line_period) < line_len else 0.0
	if hud.echo_env > 0.0 and not cam.is_position_behind(B.phone_pos):
		hud.echo_pos = cam.unproject_position(B.phone_pos + Vector3(0, 0.75, 0))
	var t_db := -30.0
	var t_cut := 800.0
	var t_wet := 0.45
	var t_wall := -60.0
	var from := Vector3.ZERO
	var ac: Array = ROOM_AC.get(cam_room, ROOM_AC["s"])
	var t_pipe := 0.0
	if meta != null and cam_room != "":
		var stl: Dictionary = B.styles[cam_room]
		ac = AC_BY.get(stl.get("ac", stl.step), AC_BY["concrete"])
	if state == St.TITLE or state == St.LABMENU or (state == St.TRANSITION and hud.mode == "title"):
		t_db = -25.0
		t_cut = 1100.0
		t_wet = 0.55
		bell_src = cam.global_position + Vector3(-1.0, 3.0, -6.0)
		hud.aid_level = 0.2
		hud.aid_muffle = 0.8
		hud.aid_dir = Vector2.ZERO
		hud.wall_level = 0.0
	else:
		var lpos := player.global_position
		var q := field.query(lpos)
		var cost: float = q.cost
		var mf: float = q.muffle
		t_db = clampf(-0.72 * cost, -42.0, 0.0) - 2.0 + src_db
		t_pipe = clampf(float(q.get("pipe", 0.0)), 0.0, 1.0)
		t_cut = clampf(15000.0 * pow(0.26, mf) / (1.0 + cost / 50.0), 380.0, 15000.0)
		t_wet = clampf(0.06 + cost / 55.0 + mf * 0.1 + float(ac[2]), 0.04, 0.62)
		var flat := Vector2(field.phone_pos.x - lpos.x, field.phone_pos.z - lpos.z).length()
		# with a clear path the brass covers it; it only matters where the air route is shut or long
		t_wall = clampf(-4.0 - 2.4 * flat, -60.0, -8.0) - maxf(0.0, 12.0 - cost) + wall_gain
		bell_wall.global_position = listener.global_position + Vector3(field.phone_pos.x - lpos.x, 0, field.phone_pos.z - lpos.z).normalized() * 3.0 if flat > 0.3 else listener.global_position
		from = q.from
		var dv := Vector3(from.x - lpos.x, 0, from.z - lpos.z)
		if dv.length() < 0.4:
			dv = Vector3(field.phone_pos.x - lpos.x, 0, field.phone_pos.z - lpos.z)
		dv = dv.normalized()
		var goal := listener.global_position + dv * 3.0
		bell_src = bell_src.lerp(goal, minf(1.0, delta * 4.0))
		hud.aid_level = clampf(1.0 + t_db / 34.0, 0.0, 1.0)
		hud.aid_muffle = clampf(mf, 0.0, 1.0)
		hud.aid_dir = _screen_dir(dv) if not bell_stopped else Vector2.ZERO
		hud.wall_dir = _screen_dir(Vector3(field.phone_pos.x - lpos.x, 0, field.phone_pos.z - lpos.z))
		hud.wall_level = clampf(1.0 + t_wall / 30.0, 0.0, 1.0) if not bell_stopped else 0.0
		if bell_stopped:
			hud.aid_level = 0.0
	var busy := false
	for d in doors:
		busy = busy or d.turning
	var k := minf(1.0, delta * (11.0 if busy else 3.5))
	wall_db = lerpf(wall_db, t_wall if not bell_stopped else -60.0, minf(1.0, delta * 3.0))
	bell_wall.volume_db = wall_db
	rv.room_size = lerpf(rv.room_size, ac[0], minf(1.0, delta * 2.0))
	rv.damping = lerpf(rv.damping, ac[1], minf(1.0, delta * 2.0))
	srv.wet = lerpf(srv.wet, ac[3], minf(1.0, delta * 2.0))
	srv.room_size = lerpf(srv.room_size, ac[0] * 0.8, minf(1.0, delta * 2.0))
	srv.damping = lerpf(srv.damping, ac[1], minf(1.0, delta * 2.0))
	bell_db = lerpf(bell_db, t_db, k)
	bell_cut = lerpf(bell_cut, t_cut, k)
	bell_wet = lerpf(bell_wet, t_wet, k)
	pipe_s = lerpf(pipe_s, t_pipe, k)
	hud.aid_pipe = pipe_s
	bell.volume_db = bell_db + linear_to_db(maxf(1.0 - 0.9 * pipe_s, 0.05))
	bell.global_position = bell_src
	if bell_pipe != null:
		bell_pipe.volume_db = bell_db + linear_to_db(maxf(pipe_s, 0.001)) if not bell_stopped else -60.0
		bell_pipe.global_position = bell_src
	lp.cutoff_hz = bell_cut
	rv.wet = bell_wet
	var ag := linear_to_db(maxf(amb_gain * amb_duck, 0.0001))
	amb.volume_db = -22.0 + ag
	for p: AudioStreamPlayer3D in loops:
		p.volume_db = float(p.get_meta("base")) + ag
	for p2: AudioStreamPlayer in amb_extra:
		p2.volume_db = float(p2.get_meta("base")) + ag

## a direction on the floor, as it appears on the screen (x right, y down)
func _screen_dir(dv: Vector3) -> Vector2:
	if dv.length() < 0.01:
		return Vector2.ZERO
	dv = dv.normalized()
	var b := cam.global_transform.basis
	var fwd := -b.z
	fwd.y = 0
	if fwd.length() < 0.2:
		fwd = b.y
		fwd.y = 0
	return Vector2(dv.dot(b.x), -dv.dot(fwd.normalized())).normalized()

func _on_footstep() -> void:
	if state == St.TITLE:
		return
	sfx("step_%s_%d" % [step_surface, randi() % 5], -15.0 if step_surface != "carpet" else -11.0, randf_range(0.9, 1.08))


# ------------------------------------------------------------------ QA bot
func _shot(nm: String) -> void:
	# with the visual aid on, photograph the lights while the bell is actually sounding
	var guard := 0
	while aid_on and not bell_stopped and state != St.TITLE and absf(fmod(bell.get_playback_position(), ring_period) - 0.85) > 0.12 and guard < 900:
		guard += 1
		await get_tree().process_frame
	if Story.chapter > 1 and not lab:
		nm = "c%d_%s" % [Story.chapter, nm]
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shot_dir, nm])
	print("shot %-22s bell %6.1f dB  lowpass %5.0f Hz  reverb %.2f  wall %6.1f dB  cell %s" % [nm, bell_db, bell_cut, bell_wet, wall_db, Building.world_to_cell(player.global_position)])

func _bot_until(cond: Callable, limit := 40.0) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > limit:
			return false
	return true

func _bot_goto(target: Vector3, limit := 12.0) -> bool:
	var t := 0.0
	while true:
		if state == St.BUSY:
			bot_vec = Vector3.ZERO
			await get_tree().process_frame
			t += get_process_delta_time()
			if t > limit + 8.0:
				bot_fail = "stuck in a cut-scene"
				return false
			continue
		var dv := Vector3(target.x - player.global_position.x, 0, target.z - player.global_position.z)
		if dv.length() < 0.1:
			break
		bot_vec = dv.normalized() * minf(1.0, dv.length() * 4.0 + 0.2)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > limit or (state != St.PLAY and state != St.BUSY):
			bot_vec = Vector3.ZERO
			bot_fail = "could not walk to %s (stuck at %s, state %d)" % [target, player.global_position, state]
			return false
	bot_vec = Vector3.ZERO
	# wherever the bot stops, the player has to be on the screen
	if state == St.PLAY and not cam_override and not lab:
		for i in 4:
			await get_tree().process_frame
		if state == St.PLAY and not cam_override and story.lost():
			bot_fail = "the camera lost the player at %s (cell %s)" % [player.global_position, Building.world_to_cell(player.global_position)]
			return false
	return true

func _bot_walk_cell(to: Vector2i) -> bool:
	var from := Building.world_to_cell(player.global_position)
	if from == to:
		return await _bot_goto(Building.cell_center(to))
	var d := LevelLogic.DIRV.find(to - from)
	if d < 0:
		bot_fail = "non adjacent step %s -> %s" % [from, to]
		return false
	var portal := B.portal_center(LevelLogic.edge_key(from, d))
	var dv := Building.dir_vec(d)
	if not await _bot_goto(Building.cell_center(from)):
		return false
	if not await _bot_goto(portal - dv * 0.5):
		return false
	if not await _bot_goto(portal + dv * 0.5):
		return false
	return await _bot_goto(Building.cell_center(to))

func _bot_to_door(d: Door) -> bool:
	if state == St.DOOR:
		return cur_door == d
	if not await _bot_goto(Building.cell_center(L.op_cell(d.index))):
		return false
	if not await _bot_goto(d.rider_world(true)):
		return false
	await get_tree().process_frame
	await get_tree().process_frame
	return true

func _bot_play(actions: Array, shots: bool) -> bool:
	var turn_no := 0
	for i in actions.size():
		var a: Dictionary = actions[i]
		match a.t:
			"walk":
				if state == St.DOOR:
					_on_act()
					await _bot_until(func() -> bool: return state == St.PLAY)
				if not await _bot_walk_cell(a.to):
					return false
			"attach":
				var d := doors[a.door]
				if not await _bot_to_door(d):
					return false
				if not intro_done:
					_on_act()
					await wait(1.3)
					if shots:
						await _shot("03_no_knob")
					await wait(2.5)
					if shots:
						await _shot("04_pocket")
					await wait(1.5)
					if shots:
						await _shot("04b_knob_in_hand")
					await _bot_until(func() -> bool: return state == St.PLAY)
					await wait(0.3)
					if shots:
						await _shot("05_knob_found")
				_on_act()
				if shots and turn_no == 0:
					await wait(0.9)
					await _shot("06_attach")
				if not await _bot_until(func() -> bool: return state == St.DOOR):
					bot_fail = "attach did not reach door mode"
					return false
			"turn":
				var d := doors[a.door]
				if state != St.DOOR:
					if not await _bot_to_door(d):
						return false
					_on_act()
					if not await _bot_until(func() -> bool: return state == St.DOOR):
						bot_fail = "grab failed"
						return false
				var opt := {}
				for o: Dictionary in arrow_opts:
					if o.pos == a.pos:
						opt = o
				if opt.is_empty():
					bot_fail = "turn option missing for door %d -> %d" % [d.def.id, a.pos]
					return false
				turn_no += 1
				if shots:
					await _shot("1%d_door%d_before" % [turn_no, d.def.id])
				_door_choose(opt)
				await wait(1.2)
				if shots:
					await _shot("1%d_door%d_turning" % [turn_no, d.def.id])
				if not await _bot_until(func() -> bool: return state == St.DOOR):
					bot_fail = "turn did not finish"
					return false
				if Building.world_to_cell(player.global_position) != a.to:
					bot_fail = "after turning door %d the player is in %s, rules say %s" % [d.def.id, Building.world_to_cell(player.global_position), a.to]
					return false
			"detach":
				var d := doors[a.door]
				if state == St.DOOR:
					_on_back()
				else:
					if not await _bot_to_door(d):
						return false
					_on_back()
				await wait(0.2)
				if not await _bot_until(func() -> bool: return state == St.PLAY):
					return false
				if L.knob_on != -1:
					bot_fail = "knob not taken"
					return false
				if shots:
					await _shot("2%d_room_%s" % [turn_no, cam_room])
	return true

## play the solver's shortest answer on a test board in the real engine: proves the board loads,
## the doors carry the player where the rules say, and the telephone can be answered.
func _bot_lab() -> void:
	Engine.time_scale = 4.0
	await wait(1.2)
	await _shot("lab_%s_start" % lab_file)
	var res := Solver.search(L, Building.world_to_cell(player.global_position))
	var ok: bool = res.found and await _bot_play(res.actions, false)
	if ok:
		if state == St.DOOR:
			_on_act()
			await _bot_until(func() -> bool: return state == St.PLAY)
		await _bot_goto(B.phone_pos + Vector3(0, 0, 0.9))
		await get_tree().process_frame
		await get_tree().process_frame
		ok = near_phone
		if not ok:
			bot_fail = "phone not in reach"
		else:
			_on_act()
			ok = await _bot_until(func() -> bool: return state == St.LABDONE, 20.0)
			await _shot("lab_%s_done" % lab_file)
	print("LABBOT %s %s turns=%d shortest=%d %s" % ["OK" if ok else "FAIL", lab_file, lab_turns, lab_min, bot_fail])
	get_tree().quit(0 if ok else 1)

func _bot_autoplay() -> void:
	Engine.time_scale = 3.0
	if state == St.TITLE:
		await wait(5.0)
		await _shot("01_title")
		_start_game()
	await _bot_until(func() -> bool: return state == St.PLAY)
	await wait(1.5)
	await _shot("02_corridor")
	var res := Solver.search(L, Building.world_to_cell(player.global_position))
	var ok: bool = res.found and await _bot_play(res.actions, true)
	if ok:
		ok = await story.bot_finish(true)
		await _shot("34_end")
	print("AUTOPLAY %s chapter %d %s" % ["OK" if ok else "FAIL", Story.chapter, bot_fail])
	get_tree().quit(0 if ok else 1)
func _bot_tour() -> void:
	await wait(3.0)
	await _shot("t_title")
	_start_game()
	await _bot_until(func() -> bool: return state == St.PLAY)
	intro_done = true
	hud.knob_known = true
	var spots := {"s": Vector3(1.4, 0, 14.6), "w": Vector3(1.5, 0, 8.0), "n": Vector3(5.0, 0, 1.6), "e": Vector3(13.4, 0, 1.7), "c": Vector3(13.5, 0, 7.6), "l": Vector3(7.0, 0, 11.6), "x": Vector3(4.4, 0, 13.4), "r": Vector3(4.3, 0, 4.4), "k": Vector3(10.6, 0, 4.6), "p": Vector3(8.2, 0, 7.2)}
	for r: String in spots:
		player.global_position = spots[r]
		await wait(1.2)
		await _shot("t_room_%s" % r)
	player.global_position = B.phone_pos + Vector3(0.2, 0, 1.0)
	await wait(1.0)
	await _shot("t_room_p2")
	for d in doors:
		player.global_position = d.rider_world(true)
		await wait(0.3)
		_on_act()
		await _bot_until(func() -> bool: return state == St.DOOR)
		await wait(0.3)
		await _shot("t_door_%d" % d.def.id)
		_on_back()
		await _bot_until(func() -> bool: return state == St.PLAY)
	print("TOUR DONE")
	get_tree().quit(0)

## random legal play, then prove the phone is still reachable by actually going there
func _bot_monkey() -> void:
	Engine.time_scale = 4.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20041113
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			rng.seed = int(a.substr(7))
	if state == St.TITLE:
		await wait(4.0)
		_start_game()
	await _bot_until(func() -> bool: return state == St.PLAY)
	var ok := true
	var turns := 0
	var log: Array[String] = []
	for n in 70:
		var cell := Building.world_to_cell(player.global_position)
		var opts := []
		for d in 4:
			if L.can_walk(cell, d):
				opts.append({"t": "walk", "to": cell + LevelLogic.DIRV[d]})
		for di in L.doors.size():
			if L.op_cell(di) != cell:
				continue
			if L.knob_on == -1:
				for k in 5:
					opts.append({"t": "attach", "door": di})
			elif L.knob_on == di:
				opts.append({"t": "detach", "door": di})
				for r: Array in L.rotations(di):
					for k in 5:
						opts.append({"t": "turn", "door": di, "pos": r[0], "to": L.op_cell(di, r[0])})
		var act: Dictionary = opts[rng.randi() % opts.size()]
		log.append(str(act))
		if act.t == "turn":
			turns += 1
		ok = await _bot_play([act], false)
		if not ok:
			break
	if ok:
		var res := Solver.search(L, Building.world_to_cell(player.global_position))
		print("monkey: %d random actions, %d door turns; knob_on=%d; solver says reachable=%s in %d turns" % [log.size(), turns, L.knob_on, res.found, res.rot])
		ok = res.found and await _bot_play(res.actions, false)
		if ok:
			ok = await story.bot_finish(false)
	if not ok:
		print("last actions: ", log.slice(-6))
	print("MONKEY %s chapter %d %s" % ["OK" if ok else "FAIL", Story.chapter, bot_fail])
	get_tree().quit(0 if ok else 1)
