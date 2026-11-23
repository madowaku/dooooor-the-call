extends SceneTree
## Godot Movie Maker entry point. See promo/README.md for invocation.

const GAME := preload("res://main.tscn")

var game: Node


func _initialize() -> void:
	_record.call_deferred()


func _record() -> void:
	seed(2004)
	Story.no_save = true
	game = GAME.instantiate()
	root.add_child(game)
	game.bot = true
	var take := OS.get_cmdline_user_args()[0]
	if take == "phone":
		await _phone()
	elif take == "basement":
		await _basement()
	elif take == "west-hall":
		await _west_hall()
	elif take == "blank-face":
		await _blank_face()
	elif take == "first-door":
		if not await _first_door():
			push_error(game.bot_fail)
			quit(1)
			return
	else:
		push_error("Unknown take: " + take)
		quit(1)
		return
	_mark("end")
	quit()


func _mark(label: String) -> void:
	print("TAKE %s frame=%d" % [label, Engine.get_frames_drawn()])


func _first_door() -> bool:
	game._start_game()
	await game._bot_until(func() -> bool: return game.state == game.St.PLAY)
	await game.wait(1.0)
	_mark("corridor")
	var result := Solver.search(game.L, game.L.start_cell)
	if not result.found:
		return false
	var prefix: Array = []
	for action: Dictionary in result.actions:
		if action.t == "turn":
			# Hold the before/after views so the changed exits have time to register.
			_watch_intro()
			if not await game._bot_play(prefix, false):
				return false
			_mark("grabbed")
			await game.wait(0.5)
			_mark("turn action")
			if not await game._bot_play([action], false):
				return false
			_mark("turn complete")
			await game.wait(1.0)
			return true
		prefix.append(action)
	return false


func _watch_intro() -> void:
	await game._bot_until(func() -> bool: return game.human.pose == "reach")
	_mark("reach")
	await game._bot_until(func() -> bool: return game.human.pose == "pocket")
	_mark("pocket")


func _phone() -> void:
	game._start_game()
	await game.wait(3.25)
	var phone: Vector3 = game.B.phone_pos
	game.cam_override = true
	game.hud.mode = "none"
	game.hud.fade = 0.0
	game.cam.global_position = phone + Vector3(0.56, 1.18, 0.78)
	game.cam.look_at(phone + Vector3(0.0, 0.69, 0.0))
	game.cam.fov = 39.0
	_mark("phone close-up")
	await game.wait(2.0)
	game.player.global_position = game.B.phone_pos + Vector3(0.0, 0.0, 0.95)
	game.phone_seen = true
	game.cam_override = false
	game._update_room(true)
	await game.wait(0.3)
	_mark("phone action")
	game._ending()
	await game._bot_until(func() -> bool: return game.bell_stopped, 4.5)
	_mark("bell stops")
	# Quit before the receiving line plays any story clues.
	await game.wait(1.1)


func _west_hall() -> void:
	game._start_game()
	await game.wait(4.8)
	game.player.global_position = Vector3(1.5, 0, 7.5)
	game._update_room(true)
	await game.wait(0.35)
	_mark("west hall walk")
	await game._bot_goto(Vector3(1.5, 0, 9.7))
	await game.wait(1.25)


func _blank_face() -> void:
	game._start_game()
	await game.wait(4.5)
	var door: Door = game.doors[0]
	var hole := door.hole_world()
	var normal := door.socket_normal()
	var along := door.pivot.global_basis.x.normalized()
	game.cam_override = true
	game.hud.mode = "none"
	game.cam.global_position = hole - normal * 0.95 - along * 0.52 + Vector3(0, 0.16, 0)
	game.cam.look_at(hole - along * 0.22 + Vector3(0, 0.10, 0))
	game.cam.fov = 53.0
	_mark("blank face")
	await game.wait(1.5)


func _basement() -> void:
	await game.wait(2.8)
	game.player.global_position = Building.cell_center(Vector2i(1, 1)) + Vector3(0.0, 0.0, 0.65)
	game._update_room(true)
	await game.wait(0.4)
	_mark("basement walk")
	await game._bot_goto(Building.cell_center(Vector2i(1, 1)) + Vector3(0.0, 0.0, -0.9))
	await game.wait(1.65)
