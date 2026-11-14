class_name Hud
extends Control
## The whole 2D overlay, drawn by hand into the 512x384 game viewport.
## The game writes the public state every frame; nothing here reads the world.

const W := 512.0
const H := 384.0
const PALE := Color(0.91, 0.87, 0.75)
const BRASS := Color(0.77, 0.61, 0.26)
const DIM := Color(0.5, 0.5, 0.46)
const KNOB_C := Vector2(468.0, 340.0)
const ACT_C := Vector2(256.0, 352.0)
const AID_C := Vector2(40.0, 340.0)

var mode: String = "none"        # "none", "title", "play", "end"
var fade: float = 0.0            # 0..1 black overlay, always topmost
var t: float = 0.0               # internal clock
var title_alpha: float = 1.0     # multiplies all title elements
var use_pad: bool = false        # pad glyphs (A / B / Y) instead of keys (Z / X / C)
var knob_known: bool = false
var knob_in_hand: bool = true
var knob_blink: float = 0.0      # seconds left of the "you don't have it" blink
var knob_flash: float = 0.0      # seconds left of the "just obtained" sparkle
var prompt_act: bool = false
var prompt_back: bool = false
var aid_on: bool = false
var aid_level: float = 0.0
var aid_muffle: float = 0.0
var aid_dir: Vector2 = Vector2.ZERO
var ring_env: float = 0.0
var end_alpha: float = 0.0
var aid_strong: bool = false     # third step of the C key: the same lights, harder
var aid_note: float = 0.0        # seconds left of the label shown when the C key changes the mode
var wall_level: float = 0.0      # the dull voice that comes straight through the walls
var wall_dir: Vector2 = Vector2.ZERO
var echo_env: float = 0.0        # the other bell, in the receiver, during the ending
var echo_pos: Vector2 = Vector2.ZERO

const AMBER := Color(1.0, 0.72, 0.3)
const DULL := Color(0.5, 0.42, 0.34)
const WALLC := Color(0.5, 0.17, 0.08)
var _ring: float = 0.0           # follows the bell: instant attack, short decay
var _ring_slow: float = 0.0      # the same, heard through a door: swollen and late
var _echo: float = 0.0

var _font: FontFile
var _logo_main: Texture2D
var _logo_sub: Texture2D
var _knob: Texture2D
var _knob_off: Texture2D


func _init() -> void:
	size = Vector2(W, H)
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST
	_font = load("res://assets/font/DotGothic16-Regular.ttf") as FontFile
	if _font:
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_logo_main = load("res://assets/tex/logo_main.png") as Texture2D
	_logo_sub = load("res://assets/tex/logo_sub.png") as Texture2D
	_knob = load("res://assets/tex/knob_icon.png") as Texture2D
	_knob_off = load("res://assets/tex/knob_icon_off.png") as Texture2D


func _process(delta: float) -> void:
	t += delta
	knob_blink = maxf(0.0, knob_blink - delta)
	knob_flash = maxf(0.0, knob_flash - delta)
	aid_note = maxf(0.0, aid_note - delta)
	_ring = 1.0 if ring_env > 0.5 else maxf(0.0, _ring - delta / 0.4)
	_ring_slow = lerpf(_ring_slow, ring_env, minf(1.0, delta * 2.6))
	_echo = 1.0 if echo_env > 0.5 else maxf(0.0, _echo - delta / 0.6)
	queue_redraw()


func _draw() -> void:
	match mode:
		"title":
			_draw_title()
		"play":
			_draw_play()
	if fade > 0.0:
		draw_rect(Rect2(0.0, 0.0, W, H), Color(0.0, 0.0, 0.0, clampf(fade, 0.0, 1.0)))
	if aid_on and _echo > 0.01 and mode != "end":
		# drawn over the black: it is still ringing after the picture is gone
		var g: float = 1.6 if aid_strong else 1.0
		draw_arc(echo_pos, 5.0 + 9.0 * (1.0 - _echo), 0.0, TAU, 20, _a(AMBER, 0.5 * _echo * g), 1.0)
		draw_arc(echo_pos, 3.0, 0.0, TAU, 12, _a(AMBER, 0.35 * _echo * g), 1.0)
	if mode == "end":
		_draw_end()


# ---------------------------------------------------------------- helpers

func _a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * clampf(a, 0.0, 1.0))


## Draws text centred on (cx, cy), snapped to whole pixels.
func _text_c(text: String, cx: float, cy: float, col: Color, fsize: int = 16) -> void:
	if _font == null or col.a <= 0.0:
		return
	var sz: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var base: float = cy + (_font.get_ascent(fsize) - _font.get_descent(fsize)) * 0.5
	draw_string(_font, Vector2(roundf(cx - sz.x * 0.5), roundf(base)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _tex_c(tex: Texture2D, c: Vector2, scale_f: float, col: Color) -> void:
	if tex == null or col.a <= 0.0:
		return
	var s: Vector2 = tex.get_size() * scale_f
	draw_texture_rect(tex, Rect2((c - s * 0.5).floor(), s), false, col)


## PS2-style button prompt: thin pale ring, dark fill, letter inside.
func _glyph(c: Vector2, letter: String, a: float, r: float = 9.0) -> void:
	draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.6 * a))
	draw_arc(c, r, 0.0, TAU, 32, _a(PALE, 0.9 * a), 1.0)
	_text_c(letter, c.x + 0.5, c.y, _a(PALE, a))


func _key(pad: String, kb: String) -> String:
	return pad if use_pad else kb


# ---------------------------------------------------------------- title

func _draw_title() -> void:
	var ta: float = clampf(title_alpha, 0.0, 1.0)
	if ta <= 0.0:
		return
	# dark band so the small print reads over the 3D background
	var top: float = 316.0
	draw_polygon(
		PackedVector2Array([Vector2(0, top), Vector2(W, top), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.72 * ta), Color(0, 0, 0, 0.72 * ta)]))
	var main_h: float = _logo_main.get_size().y if _logo_main else 51.0
	_tex_c(_logo_main, Vector2(256.0, 96.0), 1.0, _a(Color.WHITE, ta))
	if _logo_sub:
		_tex_c(_logo_sub, Vector2(256.0, 96.0 + main_h * 0.5 + 6.0 + _logo_sub.get_size().y * 0.5), 1.0, _a(Color.WHITE, ta))
	var blink: float = 0.55 + 0.45 * cos(TAU * 1.2 * t)
	_text_c("PRESS START", 256.0, 250.0, _a(PALE, ta * blink))
	var controls: String = _key("十字 移動   A けってい   B ノブ   Y 音のめやす",
		"←↑↓→ 移動   Z けってい   X ノブ   C 音のめやす")
	_text_c(controls, 256.0, 343.0, _a(DIM, 0.7 * ta))
	_text_c("ノブのない建物  ©2004", 256.0, 366.0, _a(DIM, ta))
	if aid_on:
		var tag := "音のめやす つよい" if aid_strong else "音のめやす ふつう"
		var tw: float = _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x if _font else 104.0
		draw_rect(Rect2(8.0, 358.0, tw + 8.0, 18.0), Color(0, 0, 0, 0.5 * ta))
		_text_c(tag, 12.0 + tw * 0.5, 367.0, _a(BRASS, ta))


# ---------------------------------------------------------------- play

func _draw_play() -> void:
	if aid_on:
		_draw_glow()
	if aid_note > 0.0:
		var nm := "なし"
		if aid_on:
			nm = "つよい" if aid_strong else "ふつう"
		_text_c("音のめやす " + nm, 256.0, 30.0, _a(PALE, clampf(aid_note * 2.0, 0.0, 1.0)))
	if knob_known:
		_draw_knob()
	if prompt_act:
		var p: float = 0.5 + 0.5 * sin(t * 3.2)
		_glyph(ACT_C, _key("A", "Z"), 0.78 + 0.22 * p, 9.0 + 0.5 * p)
	if prompt_back:
		_draw_back_prompt()
	if aid_on:
		_draw_aid()


func _edge_point(dv: Vector2) -> Vector2:
	var k: float = minf(W * 0.5 / maxf(absf(dv.x), 0.001), H * 0.5 / maxf(absf(dv.y), 0.001))
	return Vector2(W, H) * 0.5 + dv * k


func _blob(p: Vector2, radius: float, col: Color, alpha: float) -> void:
	for i in 14:
		draw_circle(p, radius * (1.0 - float(i) / 14.0), _a(col, alpha * 0.15))


## the bell as light on the rim of the screen.
## where: the side the sound arrives from. how big and bright: how loud.
## thin, amber, chattering with the clapper: a clear path. wide, grey, swelling late: through a shut door.
## and a second, dark red glow that always sits toward the telephone itself: the voice in the walls.
func _draw_glow() -> void:
	var gain: float = 1.7 if aid_strong else 1.0
	var lvl: float = clampf(aid_level, 0.0, 1.0)
	var muf: float = clampf(aid_muffle, 0.0, 1.0)
	if wall_level > 0.12 and wall_dir != Vector2.ZERO:
		var wp: Vector2 = _edge_point(wall_dir)
		var wa: float = wall_level * (0.25 + 0.75 * _ring_slow) * gain
		_blob(wp, 84.0, WALLC, 0.42 * wa)
		# one short, thick, dark red bar: it never chatters and never moves off the telephone
		draw_arc(wp, 22.0, 0.0, TAU, 24, Color(0, 0, 0, 0.3 * wa), 5.0)
		draw_arc(wp, 22.0, 0.0, TAU, 24, _a(Color(0.78, 0.25, 0.12), 0.75 * wa), 3.0)
	if aid_dir != Vector2.ZERO and lvl > 0.02:
		var clear: bool = muf < 0.45
		var pulse: float = _ring if clear else _ring_slow
		var chatter: float = (0.8 + 0.2 * sin(t * 201.0)) if clear and ring_env > 0.5 else 1.0
		var a: float = (0.1 + 0.5 * lvl) * (1.0 - 0.4 * muf) * (0.3 + 0.7 * pulse) * chatter * gain
		var ep: Vector2 = _edge_point(aid_dir)
		var colr: Color = AMBER.lerp(DULL, muf)
		_blob(ep, lerpf(44.0, 124.0, muf) * (0.7 + 0.5 * lvl), colr, a)
		# ripples leaving the rim: how many = how loud. whole and quick = clear air;
		# broken and slow = something shut in between. a dark under-line keeps them legible on any wall.
		var n: int = 2 + int(floorf(lvl * 2.999))
		var gap: float = 14.0
		var run: float = fmod(t * (26.0 if clear else 9.0), gap)
		for i in n:
			var r: float = 20.0 + gap * float(i) + run
			var fa: float = clampf(1.15 - (r - 20.0) / (gap * float(n) + 6.0), 0.0, 1.0) * (0.45 + 0.55 * pulse) * minf(1.0, 0.6 * gain + 0.25)
			if clear:
				draw_arc(ep, r, 0.0, TAU, 40, Color(0, 0, 0, 0.35 * fa), 3.0)
				draw_arc(ep, r, 0.0, TAU, 40, _a(colr, fa), 1.0)
			else:
				var segs: int = 14
				for k2 in segs:
					var a0: float = TAU * float(k2) / float(segs)
					draw_arc(ep, r, a0, a0 + TAU / float(segs) * lerpf(0.7, 0.35, muf), 4, Color(0, 0, 0, 0.3 * fa), 3.0)
					draw_arc(ep, r, a0, a0 + TAU / float(segs) * lerpf(0.7, 0.35, muf), 4, _a(PALE.lerp(DULL, 0.25), minf(1.0, fa * 1.4)), 1.0)


func _draw_knob() -> void:
	var c: Vector2 = KNOB_C
	var a: float = 1.0
	if aid_on and knob_blink <= 0.0:
		# the brass in the pocket answers the brass on the telephone
		var lv: float = clampf(aid_level, 0.0, 1.0)
		if aid_muffle < 0.45:
			c += (Vector2(sin(t * 201.0), cos(t * 173.0)) * (0.6 + 2.2 * lv) * _ring).round()
		elif _ring_slow > 0.02:
			var off: float = (1.0 + 2.5 * lv) * _ring_slow
			var gt: Texture2D = _knob if knob_in_hand else _knob_off
			_tex_c(gt, KNOB_C + Vector2(off, 0), 2.0, Color(1, 1, 1, 0.3))
			_tex_c(gt, KNOB_C - Vector2(off, 0), 2.0, Color(1, 1, 1, 0.3))
	if knob_blink > 0.0:
		var k: float = clampf(knob_blink * 3.0, 0.0, 1.0)
		c.x += roundf(sin(t * 55.0) * 2.0 * k)
		a = 1.0 if fmod(t * 10.0, 1.0) < 0.5 else 0.3
	draw_circle(KNOB_C, 27.0, Color(0, 0, 0, 0.32))
	draw_circle(KNOB_C, 21.0, Color(0, 0, 0, 0.18))
	if knob_flash > 0.0:
		var f: float = clampf(knob_flash, 0.0, 1.0)
		var grow: float = 1.0 - f
		draw_circle(KNOB_C, 18.0 + 10.0 * grow, _a(BRASS, 0.22 * f))
		draw_arc(KNOB_C, 22.0 + 12.0 * grow, 0.0, TAU, 40, _a(PALE, 0.55 * f), 1.0)
		for i in 4:
			var ang: float = t * 1.5 + float(i) * TAU / 4.0
			var p: Vector2 = KNOB_C + Vector2(cos(ang), sin(ang)) * (20.0 + 8.0 * grow)
			var g: float = 3.0 * f + 1.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -g), p + Vector2(1, 0), p + Vector2(0, g), p + Vector2(-1, 0)]), _a(PALE, f))
			draw_colored_polygon(PackedVector2Array([p + Vector2(-g, 0), p + Vector2(0, -1), p + Vector2(g, 0), p + Vector2(0, 1)]), _a(PALE, f))
	var tex: Texture2D = _knob if knob_in_hand else _knob_off
	_tex_c(tex, c, 2.0, _a(Color.WHITE, a if knob_in_hand else a * 0.8))


func _draw_back_prompt() -> void:
	var y: float = KNOB_C.y
	_glyph(Vector2(394.0, y), _key("B", "X"), 0.92)
	# tiny door with its knob, and an arrow out toward the knob icon
	var d := Rect2(410.0, y - 7.0, 8.0, 14.0)
	draw_rect(d, Color(0, 0, 0, 0.5))
	draw_rect(d, _a(DIM, 0.9), false, 1.0)
	draw_rect(Rect2(415.0, y, 2.0, 2.0), BRASS)
	var ax0: float = 421.0
	var ax1: float = 433.0
	draw_line(Vector2(ax0, y + 0.5), Vector2(ax1, y + 0.5), _a(PALE, 0.85), 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(ax1 + 3.0, y + 0.5), Vector2(ax1 - 1.0, y - 3.0), Vector2(ax1 - 1.0, y + 4.0)]), _a(PALE, 0.85))


func _draw_aid() -> void:
	var c: Vector2 = AID_C
	if ring_env > 0.5:
		c += Vector2(sin(t * 53.0), cos(t * 47.0)).round()
	var lvl: float = clampf(aid_level, 0.0, 1.0)
	var muf: float = clampf(aid_muffle, 0.0, 1.0)
	draw_circle(AID_C, 17.0, Color(0, 0, 0, 0.3))
	# arcs to the upper right: count and brightness follow loudness, dashes follow muffling
	var n: int = int(ceilf(lvl * 4.0 - 0.001))
	var span: float = 0.55
	var mid: float = -PI * 0.25
	for i in n:
		var r: float = 13.0 + 3.0 * float(i)
		var a: float = (0.35 + 0.65 * clampf(lvl * 4.0 - float(i), 0.0, 1.0)) * (1.0 - 0.55 * muf) * (0.65 + 0.35 * ring_env)
		var col: Color = _a(PALE, a)
		if muf < 0.3:
			draw_arc(c, r, mid - span, mid + span, 12, col, 1.0)
		else:
			var gap: float = lerpf(0.25, 0.7, (muf - 0.3) / 0.7)
			var segs: int = 3 + i
			var step: float = span * 2.0 / float(segs)
			for s in segs:
				var a0: float = mid - span + step * float(s)
				draw_arc(c, r, a0, a0 + step * (1.0 - gap), 4, col, 1.0)
	_draw_phone(c)
	if aid_dir != Vector2.ZERO:
		var dv: Vector2 = aid_dir.normalized()
		var tip: Vector2 = AID_C + dv * 30.0
		var side: Vector2 = Vector2(-dv.y, dv.x) * 3.5
		var back: Vector2 = AID_C + dv * 24.0
		draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), _a(BRASS, 0.95))


## Rotary phone silhouette (~22px wide): black, with a faint pale rim so it reads on dark rooms.
func _draw_phone(c: Vector2) -> void:
	var rim: Color = _a(PALE, 0.45)
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		_phone_shape(c + o, rim)
	_phone_shape(c, Color(0.02, 0.02, 0.02))
	draw_arc(c + Vector2(0, 3), 3.5, 0.0, TAU, 16, _a(DIM, 0.9), 1.0)
	draw_rect(Rect2(c + Vector2(-0.5, 2.5), Vector2(1, 1)), _a(DIM, 0.9))


func _phone_shape(c: Vector2, col: Color) -> void:
	# body: rounded trapezoid
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-6, -3), c + Vector2(6, -3), c + Vector2(9, 3),
		c + Vector2(10, 8), c + Vector2(-10, 8), c + Vector2(-9, 3)]), col)
	draw_circle(c + Vector2(-8, 7), 2.0, col)
	draw_circle(c + Vector2(8, 7), 2.0, col)
	# cradle and handset
	draw_rect(Rect2(c + Vector2(-6, -5), Vector2(3, 2)), col)
	draw_rect(Rect2(c + Vector2(3, -5), Vector2(3, 2)), col)
	draw_rect(Rect2(c + Vector2(-9, -9), Vector2(18, 3)), col)
	draw_rect(Rect2(c + Vector2(-11, -9), Vector2(5, 5)), col)
	draw_rect(Rect2(c + Vector2(6, -9), Vector2(5, 5)), col)


# ---------------------------------------------------------------- end

func _draw_end() -> void:
	var a: float = clampf(end_alpha, 0.0, 1.0)
	if a <= 0.0:
		return
	_text_c("DOOOOOR: THE CALL", 256.0, 192.0, _a(PALE, a))
