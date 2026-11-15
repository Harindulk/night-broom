extends Node2D
# Night Broom: fly a witch through Halloween night. Ghosts possess your keys.

const W := 480.0
const H := 270.0
const PLAY_TOP := 34.0
const PLAY_BOTTOM := 200.0
const GROUND_Y := 214.0
const NIGHT_LEN := 120.0
const TILES := preload("res://assets/sprites/tiles.png")
const TILES_MONO := preload("res://assets/sprites/tiles_mono.png")
const FONT := preload("res://assets/fonts/kenpixel.ttf")

const DIRS := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
const DIR_ROT := [0.0, PI, -PI / 2, PI / 2]
const KEYS := [[KEY_UP, KEY_W], [KEY_DOWN, KEY_S], [KEY_LEFT, KEY_A], [KEY_RIGHT, KEY_D]]
const OPPOSITE := [1, 0, 3, 2]
# inverted-T keycap layout, screen space
const KEY_POS := [Vector2(240, 228), Vector2(240, 252), Vector2(215, 252), Vector2(265, 252)]

const C_WITCH := Color(0.62, 1.0, 0.55)
const C_BAT := Color(1.0, 0.42, 0.5)
const C_GHOST := Color(0.75, 0.95, 1.0)
const C_HAUNT := Color(0.72, 0.45, 1.0)
const C_PUMPKIN := Color(1.0, 0.55, 0.12)
const C_CANDY := [Color(1, 0.8, 0.2), Color(0.35, 0.75, 1), Color(1, 0.3, 0.35)]

enum S { TITLE, PLAY, END }
var state := S.TITLE

var world: Node2D
var fx: Node2D
var hud: CanvasLayer
var bg: Node2D
var cam: Camera2D

var witch: Node2D
var witch_body: Sprite2D
var vel := Vector2.ZERO
var hearts := 3
var invuln := 0.0
var candy := 0
var best := 0
var t := 0.0
var end_t := 0.0
var won := false

var key_map := [0, 1, 2, 3]  # key index -> direction index
var key_down := [false, false, false, false]
var key_caps: Array = []      # [{cap, icon, ghost, haunt_left}]
var flying_ghosts := 0

var candies: Array = []
var bats: Array = []
var pumpkins: Array = []
var particles: Array = []
var stars: Array = []

var bat_timer := 2.0
var haunt_timer := 11.0
var pumpkin_timer := 4.0
var first_haunt_done := false
var shake := 0.0
var combo := 0
var combo_t := 0.0

var lbl_candy: Label
var heart_sprites: Array = []
var time_bar: ColorRect
var moon: Sprite2D
var title_box: Control
var end_box: Control
var lbl_end_title: Label
var lbl_end_score: Label
var lbl_hint: Label

var sfx := {}
var bot_mode := false  # ?bot=1 on web: publish state for the automated playtest
var music: AudioStreamPlayer
var tex_cache := {}
var flash_rect: ColorRect
var scenery: Node2D
var windows: Array = []  # [pos, dawn threshold] village windows that light up at dawn
var sun: Sprite2D
var dawn := 0.0
var ambient: Array = []  # title/end screen drifters
var ambient_timer := 0.0


func _ready() -> void:
	randomize()
	_load_best()
	cam = Camera2D.new()
	cam.position = Vector2(W / 2, H / 2)
	add_child(cam)
	bg = Node2D.new()
	bg.draw.connect(_draw_bg)
	add_child(bg)
	_build_scenery()
	world = Node2D.new()
	add_child(world)
	fx = Node2D.new()
	fx.z_index = 5
	fx.draw.connect(_draw_fx)
	add_child(fx)
	hud = CanvasLayer.new()
	add_child(hud)
	_build_witch()
	_build_hud()
	_build_audio()
	for i in 70:
		stars.append([Vector2(randf() * W, randf() * (GROUND_Y - 30)), randf() * TAU, randf_range(0.3, 1.0)])
	_show_title()
	if OS.has_feature("web"):
		bot_mode = str(JavaScriptBridge.eval("location.search")).contains("bot=1")


# ---------- helpers ----------

func tile(c: int, r: int, mono := false) -> AtlasTexture:
	var k := Vector3i(c, r, int(mono))
	if not tex_cache.has(k):
		var a := AtlasTexture.new()
		a.atlas = TILES_MONO if mono else TILES
		a.region = Rect2(c * 16, r * 16, 16, 16)
		tex_cache[k] = a
	return tex_cache[k]


func spr(c: int, r: int, col: Color, parent: Node, mono := false) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tile(c, r, mono)
	s.modulate = col
	parent.add_child(s)
	return s


func label(text: String, size: int, col: Color, parent: Node) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = 4
	ls.outline_color = Color(0.05, 0.02, 0.1)
	l.label_settings = ls
	l.text = text
	parent.add_child(l)
	return l


func centered(l: Label, y: float) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, y)
	l.size = Vector2(W, 0)


func play(name: String, pitch := 1.0, vol := 0.0) -> void:
	var p: AudioStreamPlayer = sfx[name]
	p.pitch_scale = pitch
	p.volume_db = vol
	p.play()


var _hitstop_id := 0
func hitstop(dur: float, scale := 0.05) -> void:
	_hitstop_id += 1
	var my := _hitstop_id
	Engine.time_scale = scale
	await get_tree().create_timer(dur, true, false, true).timeout
	if my == _hitstop_id:
		Engine.time_scale = 1.0


func flash(col: Color, dur := 0.2) -> void:
	flash_rect.color = col
	create_tween().tween_property(flash_rect, "color:a", 0.0, dur)


func burst(pos: Vector2, col: Color, n: int, speed := 90.0) -> void:
	if particles.size() > 500:
		return
	for i in n:
		var a := randf() * TAU
		particles.append({"p": pos, "v": Vector2.from_angle(a) * randf_range(speed * 0.3, speed), "life": randf_range(0.3, 0.7), "max": 0.7, "c": col, "s": randf_range(1.0, 2.5)})


func popup(text: String, pos: Vector2, col: Color) -> void:
	var l := label(text, 16, col, world)
	l.z_index = 6
	l.position = pos - Vector2(12, 14)
	l.scale = Vector2(1.6, 1.6)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y - 18, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.tween_callback(l.queue_free)


# ---------- building ----------

func _build_scenery() -> void:
	var layer := Node2D.new()
	add_child(layer)
	scenery = layer
	layer.draw.connect(_draw_windows)
	sun = spr(27, 11, Color(1.0, 0.85, 0.4), layer, true)
	sun.scale = Vector2(3, 3)
	sun.visible = false
	moon = spr(20, 5, Color(1.0, 0.95, 0.75), layer, true)
	moon.scale = Vector2(3, 3)
	# village silhouettes along the horizon
	var x := 6.0
	var houses := [Vector2i(2, 19), Vector2i(3, 20), Vector2i(4, 21), Vector2i(0, 1), Vector2i(6, 20), Vector2i(2, 1), Vector2i(7, 21), Vector2i(5, 19), Vector2i(8, 20), Vector2i(3, 1), Vector2i(1, 21), Vector2i(9, 19)]
	var i := 0
	while x < W:
		var h: Vector2i = houses[i % houses.size()]
		var s := spr(h.x, h.y, Color(0.2, 0.14, 0.32), layer)
		var sc := 2.0 if h.y > 10 else 1.5
		s.scale = Vector2(sc, sc)
		s.position = Vector2(x + 8 * sc, GROUND_Y - 8 * sc)
		windows.append([s.position + Vector2(randf_range(-5, 3) * sc, randf_range(-2, 4) * sc), randf_range(0.15, 0.95)])
		x += 16 * sc + randf_range(2, 10)
		i += 1
	# porch pumpkins
	for px in [70.0, 180.0, 330.0, 420.0]:
		var p := spr(33, 18, C_PUMPKIN, layer, true)
		p.position = Vector2(px, GROUND_Y - 6)
		p.scale = Vector2(0.75, 0.75)


func _build_witch() -> void:
	witch = Node2D.new()
	witch.position = Vector2(W / 2, 126)
	witch.z_index = 3
	world.add_child(witch)
	var broom := spr(34, 3, Color(0.85, 0.6, 0.35), witch)
	broom.rotation = PI / 4  # staff tile is diagonal; lay it flat
	broom.position = Vector2(-1, 7)
	broom.scale = Vector2(1.2, 0.9)
	witch_body = spr(26, 9, C_WITCH, witch, true)
	witch_body.position = Vector2(0, -3)
	witch.scale = Vector2(1.5, 1.5)


func _build_hud() -> void:
	# ground strip that holds the keyboard
	var ground := ColorRect.new()
	ground.color = Color(0.09, 0.06, 0.15)
	ground.position = Vector2(0, GROUND_Y)
	ground.size = Vector2(W, H - GROUND_Y)
	hud.add_child(ground)
	var edge := ColorRect.new()
	edge.color = Color(0.3, 0.2, 0.45)
	edge.position = Vector2(0, GROUND_Y)
	edge.size = Vector2(W, 1)
	hud.add_child(edge)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.size = Vector2(W, GROUND_Y)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(flash_rect)
	for k in 4:
		var cap := Node2D.new()
		cap.position = KEY_POS[k]
		hud.add_child(cap)
		var base := spr(25, 15, Color(0.85, 0.82, 0.9), cap)
		base.scale = Vector2(1.4, 1.4)
		var icon := spr(28, 21, Color(0.12, 0.08, 0.2), cap, true)
		icon.rotation = DIR_ROT[k]
		var g := spr(27, 8, C_GHOST, cap)
		g.position = Vector2(14, -13)
		g.z_index = 1
		var tb := ColorRect.new()
		tb.color = C_HAUNT.lightened(0.4)
		tb.position = Vector2(-11, 12)
		tb.size = Vector2(22, 2)
		tb.visible = false
		cap.add_child(tb)
		g.visible = false
		key_caps.append({"cap": cap, "base": base, "icon": icon, "ghost": g, "bar": tb, "haunt": 0.0, "haunt_max": 1.0})
	var kl := label("arrows / WASD", 8, Color(0.6, 0.55, 0.75), hud)
	kl.position = Vector2(290, 248)
	# top bar: candy, time, hearts
	var ci := spr(34, 10, Color.WHITE, hud)
	ci.position = Vector2(14, 12)
	lbl_candy = label("0", 16, Color(1, 0.95, 0.8), hud)
	lbl_candy.position = Vector2(24, 1)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.2, 0.15, 0.3)
	bar_bg.position = Vector2(170, 10)
	bar_bg.size = Vector2(140, 4)
	hud.add_child(bar_bg)
	time_bar = ColorRect.new()
	time_bar.color = Color(1.0, 0.8, 0.4)
	time_bar.position = Vector2(170, 10)
	time_bar.size = Vector2(0, 4)
	hud.add_child(time_bar)
	var sun := spr(27, 11, Color(1, 0.8, 0.4), hud)
	sun.position = Vector2(320, 12)
	sun.scale = Vector2(0.7, 0.7)
	var dl := label("DAWN", 8, Color(1, 0.8, 0.4), hud)
	dl.position = Vector2(330, 4)
	for i in 3:
		var hs := spr(39, 10, Color.WHITE, hud)
		hs.position = Vector2(W - 14 - i * 16, 12)
		heart_sprites.append(hs)
	# title
	title_box = Control.new()
	hud.add_child(title_box)
	centered(label("NIGHT BROOM", 32, Color(1, 0.7, 0.25), title_box), 26)
	centered(label("grab candy   dodge bats   survive till dawn", 16, Color(0.95, 0.9, 1), title_box), 62)
	centered(label("ghosts will haunt your keys. the keycaps below show where each key flies you NOW", 8, Color(0.8, 0.65, 1), title_box), 82)
	lbl_hint = label("press an arrow key to fly", 16, Color(1, 1, 1), title_box)
	centered(lbl_hint, 158)
	# end
	end_box = Control.new()
	end_box.visible = false
	hud.add_child(end_box)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.08, 0.55)
	dim.position = Vector2(0, 30)
	dim.size = Vector2(W, 160)
	end_box.add_child(dim)
	lbl_end_title = label("", 32, Color(1, 0.7, 0.25), end_box)
	centered(lbl_end_title, 50)
	lbl_end_score = label("", 16, Color(1, 1, 1), end_box)
	centered(lbl_end_score, 96)
	var again := label("press any key to fly again", 16, Color(0.85, 0.8, 1), end_box)
	centered(again, 160)


func _build_audio() -> void:
	for n in ["pickup", "pumpkin", "haunt", "hit", "exorcise", "dawn", "start", "key", "glitch", "err", "whoosh"]:
		var p := AudioStreamPlayer.new()
		var path := "res://assets/sfx/%s.%s" % [n, "ogg" if n in ["key", "glitch", "err", "whoosh"] else "mp3"]
		p.stream = load(path)
		add_child(p)
		sfx[n] = p
	music = AudioStreamPlayer.new()
	var m: AudioStreamMP3 = load("res://assets/music/danse.mp3")
	m.loop = true
	music.stream = m
	music.volume_db = -8
	add_child(music)


# ---------- state ----------

func _show_title() -> void:
	state = S.TITLE
	title_box.visible = true
	end_box.visible = false


func _start() -> void:
	state = S.PLAY
	title_box.visible = false
	end_box.visible = false
	t = 0.0
	candy = 0
	combo = 0
	hearts = 3
	invuln = 0.0
	vel = Vector2.ZERO
	witch.position = Vector2(W / 2, 110)
	witch.visible = true
	key_map = [0, 1, 2, 3]
	for k in 4:
		_unhaunt(k, false)
	for arr in [candies, bats, pumpkins]:
		for e in arr:
			e.node.queue_free()
		arr.clear()
	bat_timer = 2.5
	haunt_timer = 11.0
	pumpkin_timer = 4.0
	first_haunt_done = false
	for a in ambient:
		a.node.queue_free()
	ambient.clear()
	for i in 3:
		_spawn_candy()
	_refresh_hud()
	play("start")
	if not music.playing:
		music.play()


func _end(did_win: bool) -> void:
	state = S.END
	won = did_win
	end_t = 0.0
	if candy > best:
		best = candy
		_save_best()
	lbl_end_title.text = "DAWN!" if did_win else "KNOCKED OFF YOUR BROOM"
	lbl_end_title.label_settings.font_size = 32 if did_win else 24
	lbl_end_score.text = "candy %d     best %d" % [candy, best]
	end_box.visible = true
	if did_win:
		play("dawn")
		burst(witch.position, Color(1, 0.8, 0.4), 40, 140)
		flash(Color(1, 0.9, 0.6, 0.6), 0.8)
	for k in 4:
		_unhaunt(k, false)
	for arr in [candies, bats, pumpkins]:
		for e in arr:
			burst(e.node.position, Color(0.8, 0.7, 1.0), 5, 50)
			e.node.queue_free()
		arr.clear()


# ---------- loop ----------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if state == S.TITLE and _key_index(e.physical_keycode) >= 0:
			_start()
		elif state == S.END and end_t > 0.8:
			_start()


func _key_index(code: int) -> int:
	for k in 4:
		if code in KEYS[k]:
			return k
	return -1


func _process(dt: float) -> void:
	_read_keys()
	if state == S.PLAY:
		_update_play(dt)
	else:
		end_t += dt
		witch.position.y += sin(Time.get_ticks_msec() / 300.0) * 0.15
		lbl_hint.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() / 220.0)
		_update_ambient(dt)
	dawn = clamp((t - (NIGHT_LEN - 20.0)) / 20.0, 0.0, 1.0) if state == S.PLAY or won else 0.0
	sun.visible = dawn > 0.0
	sun.position = Vector2(70, GROUND_Y + 24 - dawn * 90)
	scenery.modulate = Color.WHITE.lerp(Color(1.5, 1.25, 1.1), dawn)
	scenery.position.x = (W / 2 - witch.position.x) * 0.05  # parallax
	_update_caps(dt)
	_update_particles(dt)
	# trauma shake: quadratic, smooth, self-decaying
	shake = maxf(shake - 1.6 * dt, 0.0)
	var tr := shake * shake
	var ms := Time.get_ticks_msec() / 1000.0 * 30.0
	cam.offset = Vector2(7 * tr * sin(ms * 1.7), 5 * tr * sin(ms * 2.3))
	bg.queue_redraw()
	scenery.queue_redraw()
	fx.queue_redraw()
	if bot_mode:
		_publish_state()


func _read_keys() -> void:
	for k in 4:
		var d := false
		for code in KEYS[k]:
			if Input.is_physical_key_pressed(code):
				d = true
		if d and not key_down[k] and state == S.PLAY:
			play("key", randf_range(0.9, 1.1), -10)
		key_down[k] = d


func _update_play(dt: float) -> void:
	t += dt
	if t >= NIGHT_LEN:
		_end(true)
		return
	# movement through the (possibly haunted) key map
	var input := Vector2.ZERO
	for k in 4:
		if key_down[k]:
			input += DIRS[key_map[k]]
	vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * dt))
	if input != Vector2.ZERO:
		vel += input.normalized() * 950.0 * dt
	vel = vel.limit_length(150.0)
	witch.position += vel * dt
	witch.position.x = clamp(witch.position.x, 10, W - 10)
	witch.position.y = clamp(witch.position.y, PLAY_TOP, PLAY_BOTTOM)
	witch.rotation = lerp(witch.rotation, vel.x / 150.0 * 0.35, 10 * dt)
	witch_body.position.y = -3 + sin(t * 6.0) * 0.8
	witch_body.flip_h = vel.x < -5 if abs(vel.x) > 5 else witch_body.flip_h
	if randf() < 0.6 and particles.size() < 500:
		particles.append({"p": witch.position + Vector2(-sign(vel.x + 0.01) * 10, 6), "v": -vel * 0.2 + Vector2(0, 10), "life": 0.5, "max": 0.5, "c": Color(0.75, 0.6, 1.0), "s": 1.5})
	invuln = max(invuln - dt, 0.0)
	witch.modulate.a = 0.35 if invuln > 0 and int(invuln * 20) % 2 == 0 else 1.0
	_update_candies(dt)
	_update_bats(dt)
	_update_pumpkins(dt)
	_update_haunts(dt)
	time_bar.size.x = 140.0 * t / NIGHT_LEN
	var mt := t / NIGHT_LEN
	moon.position = Vector2(lerp(40.0, W - 40.0, mt), 95 - sin(mt * PI) * 38)


func _update_candies(dt: float) -> void:
	combo_t -= dt
	for c in candies.duplicate():
		var d: float = c.node.position.distance_to(witch.position)
		if d < 44:  # magnet
			c.node.position.x = move_toward(c.node.position.x, witch.position.x, 180 * dt)
			c.y = move_toward(c.y, witch.position.y, 180 * dt)
		c.node.position.y = c.y + sin(t * 3 + c.ph) * 3
		if d < 15:
			candies.erase(c)
			combo = combo + 1 if combo_t > 0 else 1
			combo = mini(combo, 5)
			combo_t = 2.2
			candy += combo
			play("pickup", 0.9 + combo * 0.12, -4)
			burst(c.node.position, c.node.get_meta("col"), 8 + combo * 3, 70 + combo * 15)
			popup("+%d" % combo, c.node.position, Color(1, 0.95, 0.6).lerp(Color(1, 0.5, 0.2), combo / 5.0))
			_squash()
			c.node.queue_free()
			_spawn_candy()
			_refresh_hud()
			lbl_candy.modulate = Color(1, 0.95, 0.6).lerp(Color(1, 0.5, 0.2), combo / 5.0)
			lbl_candy.scale = Vector2.ONE * (1.3 + combo * 0.15)
			var ct := create_tween()
			ct.tween_property(lbl_candy, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			ct.parallel().tween_property(lbl_candy, "modulate", Color.WHITE, 0.4)


func _spawn_candy() -> void:
	var p := Vector2.ZERO
	for i in 20:
		p = Vector2(randf_range(24, W - 24), randf_range(PLAY_TOP + 10, PLAY_BOTTOM - 6))
		if p.distance_to(witch.position) > 70:
			break
	var ci := randi() % 3
	var s := spr(32 + ci, 10, Color.WHITE, world)
	s.set_meta("col", C_CANDY[ci])
	s.position = p
	s.scale = Vector2.ZERO
	create_tween().tween_property(s, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	candies.append({"node": s, "y": p.y, "ph": randf() * TAU})


func _update_bats(dt: float) -> void:
	bat_timer -= dt
	if bat_timer <= 0:
		bat_timer = lerp(2.4, 0.95, t / NIGHT_LEN) * randf_range(0.7, 1.2)
		var from_left := randf() < 0.5
		var s := spr(26, 8, C_BAT, world)
		s.scale = Vector2(1.3, 1.3)
		s.flip_h = not from_left
		var y := randf_range(PLAY_TOP + 8, PLAY_BOTTOM - 4)
		s.position = Vector2(-12 if from_left else W + 12, y)
		var sp: float = lerp(70.0, 135.0, t / NIGHT_LEN) * randf_range(0.85, 1.15)
		bats.append({"node": s, "vx": sp if from_left else -sp, "y": y, "ph": randf() * TAU, "amp": randf_range(4, 18)})
	for b in bats.duplicate():
		b.node.position.x += b.vx * dt
		b.node.position.y = b.y + sin(t * 4 + b.ph) * b.amp
		b.node.scale.y = 1.3 + sin(t * 20 + b.ph) * 0.3
		if b.node.position.x < -20 or b.node.position.x > W + 20:
			bats.erase(b)
			b.node.queue_free()
		elif invuln <= 0 and b.node.position.distance_to(witch.position) < 12:
			_hurt(b)
		elif invuln <= 0 and not b.has("near") and b.node.position.distance_to(witch.position) < 26:
			b.near = true
			play("whoosh", randf_range(1.1, 1.4), -8)
			shake = minf(shake + 0.15, 1.0)
			burst(witch.position, C_BAT, 4, 50)


func _hurt(b: Dictionary) -> void:
	hearts -= 1
	invuln = 1.6
	vel = (witch.position - b.node.position).normalized() * 220
	shake = minf(shake + 0.8, 1.0)
	flash(Color(1, 0.2, 0.25, 0.3), 0.25)
	play("hit")
	burst(witch.position, C_BAT, 18, 120)
	witch_body.modulate = Color(3, 3, 3)
	create_tween().tween_property(witch_body, "modulate", C_WITCH, 0.25)
	bats.erase(b)
	b.node.queue_free()
	_refresh_hud()
	hitstop(0.09)
	if hearts <= 0:
		burst(witch.position, C_WITCH, 30, 150)
		witch.visible = false
		_end(false)


func _update_pumpkins(dt: float) -> void:
	# a jack-o'-lantern shows up while any key is haunted; grabbing it frees every key
	var haunted := 0
	for k in 4:
		if key_caps[k].haunt > 0:
			haunted += 1
	if haunted > 0 and pumpkins.is_empty():
		pumpkin_timer -= dt
		if pumpkin_timer <= 0:
			pumpkin_timer = 7.0
			var s := spr(33, 18, C_PUMPKIN, world, true)
			s.position = Vector2(randf_range(40, W - 40), randf_range(PLAY_TOP + 20, PLAY_BOTTOM - 20))
			s.scale = Vector2.ZERO
			create_tween().tween_property(s, "scale", Vector2(1.4, 1.4), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			var tag := label("FREES KEYS", 8, Color(1, 0.8, 0.5), s)
			tag.position = Vector2(-22, 8)
			tag.scale = Vector2(0.72, 0.72)
			pumpkins.append({"node": s, "life": 9.0})
	for p in pumpkins.duplicate():
		p.life -= dt
		p.node.rotation = sin(t * 5) * 0.15
		p.node.modulate = C_PUMPKIN.lightened(0.25 + 0.25 * sin(t * 8))
		if p.life < 2.0:
			p.node.visible = int(p.life * 10) % 2 == 0
		if p.node.position.distance_to(witch.position) < 15:
			pumpkins.erase(p)
			play("exorcise")
			burst(p.node.position, C_PUMPKIN, 26, 130)
			popup("+3", p.node.position, C_PUMPKIN)
			candy += 3
			if hearts < 3:
				hearts += 1
				popup("+1 life", p.node.position + Vector2(0, -14), Color(1, 0.4, 0.45))
			shake = minf(shake + 0.45, 1.0)
			flash(Color(1, 0.6, 0.2, 0.3), 0.3)
			hitstop(0.07, 0.1)
			for k in 4:
				if key_caps[k].haunt > 0:
					_unhaunt(k, true)
			p.node.queue_free()
			_refresh_hud()
		elif p.life <= 0:
			pumpkins.erase(p)
			p.node.queue_free()


# ---------- haunting (the prerequisite) ----------

func _max_haunts() -> int:
	return clampi(1 + int(t / 28.0), 1, 4)


func _update_haunts(dt: float) -> void:
	haunt_timer -= dt
	var active := flying_ghosts
	for k in 4:
		if key_caps[k].haunt > 0:
			active += 1
	if haunt_timer <= 0 and active < _max_haunts():
		haunt_timer = lerp(9.0, 4.5, t / NIGHT_LEN)
		var free_keys := []
		for k in 4:
			if key_caps[k].haunt <= 0:
				free_keys.append(k)
		if not free_keys.is_empty():
			_send_ghost(free_keys[randi() % free_keys.size()])
	for k in 4:
		var kc: Dictionary = key_caps[k]
		if kc.haunt > 0:
			kc.haunt -= dt
			kc.bar.size.x = 22.0 * kc.haunt / kc.haunt_max
			if kc.haunt <= 0:
				_unhaunt(k, true)


func _send_ghost(k: int) -> void:
	flying_ghosts += 1
	var g := spr(27, 8, C_GHOST, hud)
	g.z_index = 10
	g.position = Vector2(randf_range(60, W - 60), -16)
	g.scale = Vector2(1.6, 1.6)
	play("haunt", 1.0, -2)
	var mid := Vector2(lerp(g.position.x, KEY_POS[k].x, 0.5) + randf_range(-80, 80), 120)
	var tw := create_tween()
	tw.tween_property(g, "position", mid, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "position", KEY_POS[k] + Vector2(14, -13), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(g, "scale", Vector2.ONE, 0.5)
	tw.tween_callback(func():
		g.queue_free()
		flying_ghosts -= 1
		if state == S.PLAY:
			_haunt(k))


func _haunt(k: int) -> void:
	var cur: int = key_map[k]
	var nd: int = OPPOSITE[cur]
	if first_haunt_done and randf() < 0.5:
		var opts := [0, 1, 2, 3]
		opts.erase(cur)
		nd = opts[randi() % 3]
	key_map[k] = nd
	var kc: Dictionary = key_caps[k]
	kc.haunt = lerp(13.0, 9.0, t / NIGHT_LEN)
	kc.haunt_max = kc.haunt
	kc.ghost.visible = true
	kc.bar.visible = true
	kc.base.modulate = C_HAUNT.darkened(0.15)
	var tw := create_tween()
	tw.tween_property(kc.icon, "rotation", DIR_ROT[nd] + TAU, 0.3).from(DIR_ROT[cur]).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var tw2 := create_tween()
	tw2.tween_property(kc.cap, "scale", Vector2(1.9, 1.9), 0.12).set_ease(Tween.EASE_OUT)
	tw2.tween_property(kc.cap, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	play("glitch", 0.8)
	burst(KEY_POS[k], C_HAUNT, 14, 70)
	var hl := label("HAUNTED!", 16, C_HAUNT.lightened(0.3), hud)
	hl.position = KEY_POS[k] + Vector2(-34, -40 if k == 0 else -64)
	var tw3 := create_tween()
	tw3.tween_property(hl, "position:y", hl.position.y - 10, 1.2).set_ease(Tween.EASE_OUT)
	tw3.parallel().tween_property(hl, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tw3.tween_callback(hl.queue_free)
	shake = minf(shake + 0.45, 1.0)
	flash(C_HAUNT * Color(1, 1, 1, 0.2), 0.3)
	kc.ghost.scale = Vector2(1.5, 0.6)
	create_tween().tween_property(kc.ghost, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if not first_haunt_done:
		first_haunt_done = true
		pumpkin_timer = 1.5
		hitstop(0.5, 0.25)  # teach: slow time the first time a key gets possessed


func _unhaunt(k: int, fx_on: bool) -> void:
	var kc: Dictionary = key_caps[k]
	var was: int = key_map[k]
	key_map[k] = k
	kc.haunt = 0.0
	kc.ghost.visible = false
	kc.bar.visible = false
	kc.base.modulate = Color(0.85, 0.82, 0.9)
	kc.icon.rotation = DIR_ROT[k]
	if fx_on and was != k:
		burst(KEY_POS[k], C_GHOST, 10, 60)
		var g := spr(27, 8, C_GHOST, hud)  # the ghost visibly flees the key
		g.z_index = 10
		g.position = KEY_POS[k] + Vector2(14, -13)
		var gt := create_tween()
		gt.tween_property(g, "position", g.position + Vector2(randf_range(-70, 70), -150), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		gt.parallel().tween_property(g, "modulate:a", 0.0, 0.7).set_delay(0.2)
		gt.tween_callback(g.queue_free)
		var tw := create_tween()
		tw.tween_property(kc.icon, "rotation", DIR_ROT[k], 0.3).from(DIR_ROT[was]).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_caps(dt: float) -> void:
	for k in 4:
		var kc: Dictionary = key_caps[k]
		var target := Vector2(0, 2) if key_down[k] else Vector2.ZERO
		kc.base.position = kc.base.position.lerp(target, minf(30 * dt, 1.0))  # clamp: a slow frame made caps fly off
		kc.icon.position = kc.base.position
		if kc.haunt > 0:
			kc.ghost.position = Vector2(14, -13 + sin(t * 6 + k) * 2)
			kc.base.position.x = sin(t * 40 + k) * 0.6
			kc.icon.modulate = Color(1, 1, 1) if not key_down[k] else Color(1, 0.9, 0.5)
		else:
			kc.icon.modulate = Color(0.12, 0.08, 0.2)


func _squash() -> void:
	var tw := create_tween()
	tw.tween_property(witch_body, "scale", Vector2(1.35, 0.7), 0.05)
	tw.tween_property(witch_body, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


var _shown_hearts := 3
func _refresh_hud() -> void:
	lbl_candy.text = str(candy)
	for i in 3:
		heart_sprites[i].modulate = Color.WHITE if i < hearts else Color(0.25, 0.2, 0.3)
		if (i == hearts and hearts < _shown_hearts) or (i == hearts - 1 and hearts > _shown_hearts):
			var tw := create_tween()
			tw.tween_property(heart_sprites[i], "scale", Vector2(2.2, 2.2), 0.08)
			tw.tween_property(heart_sprites[i], "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shown_hearts = hearts


# ---------- drawing ----------

func _update_particles(dt: float) -> void:
	for p in particles.duplicate():
		p.life -= dt
		p.p += p.v * dt
		p.v *= 0.92
		if p.life <= 0:
			particles.erase(p)


func _draw_fx() -> void:
	for p in particles:
		var c: Color = p.c
		c.a = clamp(p.life / p.max, 0.0, 1.0)
		fx.draw_rect(Rect2(p.p - Vector2(p.s, p.s) * 0.5, Vector2(p.s, p.s)), c)


func _draw_bg() -> void:
	var top := Color(0.04, 0.02, 0.1).lerp(Color(0.25, 0.3, 0.6), dawn)
	var low := Color(0.18, 0.08, 0.3).lerp(Color(1.0, 0.6, 0.4), dawn)
	var bands := 12
	for i in bands:
		var y0 := GROUND_Y * i / bands
		bg.draw_rect(Rect2(0, y0, W, GROUND_Y / bands + 1), top.lerp(low, float(i) / (bands - 1)))
	var ms := Time.get_ticks_msec() / 1000.0
	var px := (W / 2 - witch.position.x) * 0.02  # parallax
	for s in stars:
		var a: float = (0.5 + 0.5 * sin(ms * 2.0 + s[1])) * s[2] * (1.0 - dawn)
		bg.draw_rect(Rect2(s[0] + Vector2(px, 0), Vector2.ONE), Color(1, 1, 0.9, a))
	if state != S.PLAY:
		moon.position = Vector2(W - 44, 150)


func _draw_windows() -> void:
	if dawn <= 0.0:
		return
	for w in windows:
		if dawn > w[1]:
			scenery.draw_rect(Rect2(w[0], Vector2(2, 2)), Color(1, 0.85, 0.4, minf((dawn - w[1]) * 8.0, 1.0)))


func _update_ambient(dt: float) -> void:
	ambient_timer -= dt
	if ambient_timer <= 0 and ambient.size() < 4:
		ambient_timer = randf_range(1.5, 3.0)
		var ghost := randf() < 0.6
		var from_left := randf() < 0.5
		var s := spr(27 if ghost else 26, 8, C_GHOST if ghost else C_BAT, world)
		s.modulate.a = 0.7
		s.flip_h = not from_left
		s.z_index = 1
		var y := randf_range(95, 185)
		s.position = Vector2(-12 if from_left else W + 12, y)
		if end_t < 2.0:  # first seconds of the title: already on screen
			s.position.x = randf_range(40, W - 40)
		var sp := randf_range(18, 30) if ghost else randf_range(45, 70)
		ambient.append({"node": s, "vx": sp if from_left else -sp, "y": y, "ph": randf() * TAU, "ghost": ghost})
	for a in ambient.duplicate():
		a.node.position.x += a.vx * dt
		a.node.position.y = a.y + sin(end_t * 2 + a.ph) * 6
		if not a.ghost:
			a.node.scale.y = 1.0 + sin(end_t * 20 + a.ph) * 0.3
		if a.node.position.x < -20 or a.node.position.x > W + 20:
			ambient.erase(a)
			a.node.queue_free()


func _publish_state() -> void:
	var st := {"state": state, "t": t, "candy": candy, "hearts": hearts, "map": key_map, "fps": Engine.get_frames_per_second(), "np": particles.size(),
		"w": [witch.position.x, witch.position.y],
		"candies": candies.map(func(c): return [c.node.position.x, c.node.position.y]),
		"bats": bats.map(func(b): return [b.node.position.x, b.node.position.y, b.vx]),
		"pumpkins": pumpkins.map(func(p): return [p.node.position.x, p.node.position.y])}
	JavaScriptBridge.eval("window.nb=" + JSON.stringify(st))


# ---------- persistence ----------

func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://best.cfg") == OK:
		best = cf.get_value("s", "best", 0)


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("s", "best", best)
	cf.save("user://best.cfg")
