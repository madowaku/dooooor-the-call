extends SceneTree
## Headless smoke test for scripts/hud.gd and shaders/post.gdshader.
## Run: godot --headless --path . -s tools/test_hud.gd


func _init() -> void:
	var hud := Hud.new()
	root.add_child(hud)
	hud.use_pad = false
	hud.knob_known = true
	hud.knob_blink = 0.5
	hud.knob_flash = 0.8
	hud.prompt_act = true
	hud.prompt_back = true
	hud.aid_on = true
	hud.aid_level = 0.8
	hud.aid_dir = Vector2(0.6, -0.8)
	hud.ring_env = 1.0
	hud.end_alpha = 1.0
	hud.fade = 0.3
	for m: String in ["none", "title", "play", "end"]:
		for pad: bool in [false, true]:
			for muffle: float in [0.0, 0.8]:
				hud.mode = m
				hud.use_pad = pad
				hud.aid_muffle = muffle
				hud.knob_in_hand = muffle < 0.5
				await process_frame
	var sh: Shader = load("res://shaders/post.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("time_s", 1.0)
	mat.set_shader_parameter("strength", 1.0)
	var rect := TextureRect.new()
	rect.material = mat
	root.add_child(rect)
	await process_frame
	await process_frame
	assert(sh != null)
	print("HUD OK")
	quit()
