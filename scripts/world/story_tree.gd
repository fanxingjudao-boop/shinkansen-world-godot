extends Node3D

# えほんのき(ファブルの木)。ちいさな おとぎばなし(寓話)が「実る」木。
# 近づくと HUD「えほんを よむ」→ やわらかい絵本オーバーレイで 3 ページの
# 小さなおはなしを読める。おはなしの主役は この世界の住人たち
# (きつね・つきのうさぎ・ゆきだるま・でんしゃ・しんじゅ・どんぐり)。
#
# 設計(instruments / ginga_railway の作法を踏襲):
# - main.gd が _spawn_extra で生成(Main.tscn / TouchHUD.tscn 不変・セーブ項目なし)。
# - HUD ボタンは実行時生成(ginga と同じ上部中央スロット)。
# - 絵本 UI は CanvasLayer を実行時生成、開いている間 get_tree().paused = true
#   (book.gd と同じ overlay 方式。UI は PROCESS_MODE_ALWAYS で動く)。
# - 読み終えると 木がうれしそうに ぽよんと はずむ + やさしいチャイム。
# - 文章は ひらがな・カタカナのみ。こわい要素なし・全おはなし やさしい結末(厳守)。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")
const WorldRefs = preload("res://scripts/world/world_refs.gd")
const RIM_SHADER = preload("res://assets/shaders/rim.gdshader")
const FONT_TITLE = preload("res://assets/fonts/MochiyPopOne-Regular.ttf")
const FONT_BODY = preload("res://assets/fonts/MPLUSRounded1c-Medium.ttf")

const TREE_POS: Vector2 = Vector2(-16.0, 14.0)   # 地上の置き場所(実機で重なれば調整)
const ENTER_RANGE: float = 7.0
const MIX_RATE: int = 22050

# ちいさな寓話たち。ぜんぶ 3 ページ・やさしい結末・ひらがなカタカナのみ。
const STORIES: Array = [
	{
		"t": "きつねと ほし",
		"c": Color(0.95, 0.45, 0.55),
		"p": [
			"よるの はらっぱに\nちいさな ほしが\nおちて いました。",
			"きつねは そっと ひろって\nたかい おかの うえから\nそらへ かえして あげました。",
			"よぞらは ありがとうって\nいつもより きらきら\nひかりました。\n\n☆ おしまい ☆",
		],
	},
	{
		"t": "つきの うさぎ",
		"c": Color(0.95, 0.75, 0.25),
		"p": [
			"つきの うさぎは\nまいばん ぺったん ぺったん\nおもちを つきます。",
			"できた おもちは\nおほしさまたちに\nおすそわけ。",
			"だから ほしは あんなに\nまるくて ぴかぴか\nなんだって。\n\n☆ おしまい ☆",
		],
	},
	{
		"t": "ゆきだるまの ぼうし",
		"c": Color(0.4, 0.65, 0.9),
		"p": [
			"さむい さむい ゆきのくに。\nことりが ぶるぶる\nふるえて いました。",
			"ゆきだるまは ぼうしを\nことりに かして あげました。\n「ぼくは さむいの へいきだよ」",
			"ことりは ぼうしの なかで\nぽかぽか ねむりました。\n\n☆ おしまい ☆",
		],
	},
	{
		"t": "でんしゃの ゆめ",
		"c": Color(0.4, 0.75, 0.5),
		"p": [
			"よるに なると でんしゃたちは\nしゃこで すやすや\nねむります。",
			"ゆめの なかでは\nほしの せんろを はしって\nつきまで とうちゃく!",
			"だから あさの でんしゃは\nあんなに うれしそうに\nはしるのです。\n\n☆ おしまい ☆",
		],
	},
	{
		"t": "うみの しんじゅ",
		"c": Color(0.55, 0.55, 0.9),
		"p": [
			"うみの そこの かいさんは\nちいさな しんじゅを\nそだてて います。",
			"まいにち「おおきく なあれ」と\nやさしく ゆらゆら\nゆすって あげます。",
			"しんじゅは うみで いちばん\nやさしい ひかりに\nなりました。\n\n☆ おしまい ☆",
		],
	},
	{
		"t": "どんぐりの き",
		"c": Color(0.9, 0.55, 0.3),
		"p": [
			"ちいさな どんぐりが\nいいました。\n「はやく おおきく なりたいな」",
			"おひさまと あめが\n「ゆっくりで いいよ」と\nひかりと みずを くれました。",
			"どんぐりは いつか みんなが\nやすめる おおきな きに\nなりました。\n\n☆ おしまい ☆",
		],
	},
]

var _player: CharacterBody3D
var _hud: Node
var _ride: Node

var _root: Node3D
var _canopy: Node3D
var _btn: BaseButton
var _btn_visible: bool = false

var _overlay: CanvasLayer
var _title_label: Label
var _body_label: Label
var _dots_label: Label
var _next_btn: Button

var _sfx: AudioStreamPlayer
var _snd_open: AudioStreamWAV
var _snd_page: AudioStreamWAV
var _snd_end: AudioStreamWAV

var _story_i: int = 0
var _page_i: int = 0


func _ready() -> void:
	var root := get_tree().root
	_player = WorldRefs.req(root, "Player", "StoryTree") as CharacterBody3D
	_hud = WorldRefs.req(root, "TouchHUD", "StoryTree")
	_ride = WorldRefs.req(root, "RideController", "StoryTree")
	_story_i = randi() % STORIES.size()
	_snd_open = _make_tone([523.25, 659.25], 0.14)
	_snd_page = _make_tone([659.25], 0.16)
	_snd_end = _make_tone([523.25, 659.25, 783.99], 0.14)
	_build_tree()
	_build_button()
	_build_overlay()


# AutoCapture(検証)用: 木のワールド座標。
func tree_position() -> Vector3:
	return _root.global_position if _root else Vector3.ZERO


func _process(_delta: float) -> void:
	if _player == null or _btn == null or _root == null:
		return
	var riding: bool = _ride != null and _ride.has_method("is_riding") and _ride.is_riding()
	var near: bool = (not riding) and _player.global_position.distance_to(_root.global_position) < ENTER_RANGE
	if near != _btn_visible:
		_btn_visible = near
		_btn.visible = near


# === 木の見た目 ===

func _build_tree() -> void:
	var gy: float = TerrainHeight.compute_height(TREE_POS.x, TREE_POS.y)
	_root = Node3D.new()
	_root.position = Vector3(TREE_POS.x, gy, TREE_POS.y)
	add_child(_root)

	# みき(すこし太め・あたたかい茶)
	var trunk := _cyl(0.34, 0.52, 2.8, Color(0.62, 0.45, 0.32))
	trunk.position = Vector3(0, 1.4, 0)
	_root.add_child(trunk)

	# こかげ(もこもこ 3 つ + てっぺんに 桜色のひとふさ)
	_canopy = Node3D.new()
	_canopy.position = Vector3(0, 3.7, 0)
	_root.add_child(_canopy)
	var puffs: Array = [
		[Vector3(0, 0, 0), 1.9, Color(0.55, 0.82, 0.5)],
		[Vector3(1.3, -0.4, 0.5), 1.25, Color(0.68, 0.88, 0.55)],
		[Vector3(-1.2, -0.3, -0.4), 1.15, Color(0.62, 0.85, 0.6)],
		[Vector3(0.2, 1.15, 0.1), 0.9, Color(1.0, 0.75, 0.85)],
	]
	for pf in puffs:
		var ball := _ball(pf[1], pf[2], 0.85)
		ball.position = pf[0]
		_canopy.add_child(ball)

	# 「実っている」ちいさな絵本たち(赤・青・黄の背表紙)
	var books: Array = [
		[Vector3(1.5, -0.9, 1.1), Color(0.9, 0.4, 0.4)],
		[Vector3(-1.4, -0.6, 0.9), Color(0.45, 0.6, 0.9)],
		[Vector3(0.4, -1.4, 1.5), Color(0.95, 0.8, 0.35)],
	]
	for bk in books:
		var b := _box(0.2, 0.3, 0.09, bk[1])
		b.position = bk[0]
		b.rotation = Vector3(0.1, randf() * TAU, 0.15)
		_canopy.add_child(b)

	# こかげが ゆっくり こきゅうする(生きている感じ・とても控えめ)
	var sway := create_tween().set_loops()
	sway.tween_property(_canopy, "scale", Vector3(1.0, 1.03, 1.0), 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(_canopy, "scale", Vector3.ONE, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 手前の 木の台 + ひらいた絵本
	var stand := Node3D.new()
	stand.position = Vector3(0, 0, 1.7)
	_root.add_child(stand)
	var post := _box(0.14, 0.9, 0.14, Color(0.72, 0.55, 0.4))
	post.position = Vector3(0, 0.45, 0)
	stand.add_child(post)
	var top := Node3D.new()
	top.position = Vector3(0, 0.95, 0)
	top.rotation.x = -0.35
	stand.add_child(top)
	var board := _box(0.8, 0.06, 0.55, Color(0.78, 0.6, 0.42))
	top.add_child(board)
	var cover := _box(0.72, 0.04, 0.5, Color(0.85, 0.4, 0.4))
	cover.position = Vector3(0, 0.05, 0)
	top.add_child(cover)
	for sx in [-1.0, 1.0]:
		var page := _box(0.34, 0.035, 0.46, Color(0.99, 0.97, 0.9))
		page.position = Vector3(sx * 0.17, 0.09, 0)
		page.rotation.z = -sx * 0.14
		top.add_child(page)

	# 空中の なまえ(駅の看板と同じ Label3D 方式)
	var name_label := Label3D.new()
	name_label.text = "えほんのき"
	name_label.font = FONT_BODY
	name_label.font_size = 96
	name_label.modulate = Color(0.6, 0.42, 0.3)
	name_label.outline_size = 18
	name_label.outline_modulate = Color(1, 1, 0.96)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0, 6.3, 0)
	_root.add_child(name_label)


# === HUD ボタン(ginga と同じ上部中央スロット・実行時生成)===

func _build_button() -> void:
	if _hud == null:
		return
	_btn = Button.new()
	_btn.name = "StoryButton"
	_btn.text = "えほんを よむ"
	# 他ワールドの乗り物ボタンと同じ 278 スロット(上部の常設ボタン列と重ならない。
	# 乗り物ボタンとは近接で同時に出ないので共存できる)
	_btn.anchor_left = 0.5
	_btn.anchor_right = 0.5
	_btn.offset_left = -140.0
	_btn.offset_top = 278.0
	_btn.offset_right = 140.0
	_btn.offset_bottom = 358.0
	_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_btn.add_theme_font_size_override("font_size", 28)
	_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.55, 0.4)   # あたたかい絵本色
	sb.set_corner_radius_all(28)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0.78, 0.42, 0.3)
	sb2.set_corner_radius_all(28)
	_btn.add_theme_stylebox_override("normal", sb)
	_btn.add_theme_stylebox_override("hover", sb)
	_btn.add_theme_stylebox_override("focus", sb)
	_btn.add_theme_stylebox_override("pressed", sb2)
	_btn.visible = false
	_btn.pressed.connect(open_book)
	_hud.add_child(_btn)


# === 絵本オーバーレイ(book.gd と同じ paused 方式・実行時生成)===

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 20
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	add_child(_overlay)

	# 音は overlay 側(ALWAYS)にぶら下げる=ポーズ中でも鳴る
	_sfx = AudioStreamPlayer.new()
	_sfx.volume_db = -12.0
	_overlay.add_child(_sfx)

	var dim := ColorRect.new()
	dim.color = Color(0.32, 0.26, 0.2, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var panel := PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(1.0, 0.97, 0.88)
	paper.set_corner_radius_all(26)
	paper.set_border_width_all(4)
	paper.border_color = Color(0.85, 0.7, 0.5)
	panel.add_theme_stylebox_override("panel", paper)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_override("font", FONT_TITLE)
	_title_label.add_theme_font_size_override("font_size", 38)
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body_label.custom_minimum_size = Vector2(560, 200)
	_body_label.add_theme_font_override("font", FONT_BODY)
	_body_label.add_theme_font_size_override("font_size", 30)
	_body_label.add_theme_color_override("font_color", Color(0.35, 0.3, 0.28))
	vbox.add_child(_body_label)

	_dots_label = Label.new()
	_dots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dots_label.add_theme_font_size_override("font_size", 22)
	_dots_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.5))
	vbox.add_child(_dots_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	vbox.add_child(row)

	var close_btn := Button.new()
	close_btn.text = "とじる"
	close_btn.custom_minimum_size = Vector2(150, 64)
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.add_theme_color_override("font_color", Color(0.45, 0.38, 0.32))
	var sbc := StyleBoxFlat.new()
	sbc.bg_color = Color(0.93, 0.88, 0.8)
	sbc.set_corner_radius_all(22)
	close_btn.add_theme_stylebox_override("normal", sbc)
	close_btn.add_theme_stylebox_override("hover", sbc)
	close_btn.add_theme_stylebox_override("focus", sbc)
	var sbc2 := StyleBoxFlat.new()
	sbc2.bg_color = Color(0.85, 0.78, 0.68)
	sbc2.set_corner_radius_all(22)
	close_btn.add_theme_stylebox_override("pressed", sbc2)
	close_btn.pressed.connect(close_book)
	row.add_child(close_btn)

	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(250, 72)
	_next_btn.add_theme_font_size_override("font_size", 30)
	_next_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	var sbn := StyleBoxFlat.new()
	sbn.bg_color = Color(0.95, 0.6, 0.35)
	sbn.set_corner_radius_all(24)
	_next_btn.add_theme_stylebox_override("normal", sbn)
	_next_btn.add_theme_stylebox_override("hover", sbn)
	_next_btn.add_theme_stylebox_override("focus", sbn)
	var sbn2 := StyleBoxFlat.new()
	sbn2.bg_color = Color(0.8, 0.47, 0.27)
	sbn2.set_corner_radius_all(24)
	_next_btn.add_theme_stylebox_override("pressed", sbn2)
	_next_btn.pressed.connect(next_page)
	row.add_child(_next_btn)


# === 開く / めくる / とじる ===

func open_book() -> void:
	if _overlay == null or _overlay.visible:
		return
	_page_i = 0
	_render_page()
	if _btn:
		_btn.visible = false
		_btn_visible = false
	_overlay.visible = true
	get_tree().paused = true
	_play(_snd_open)


func next_page() -> void:
	if _overlay == null or not _overlay.visible:
		return
	var pages: Array = STORIES[_story_i]["p"]
	if _page_i >= pages.size() - 1:
		# さいごのページ →「おしまい!」= とじて 木が よろこぶ
		_finish_book()
		return
	_page_i += 1
	_render_page()
	_play(_snd_page)


func close_book() -> void:
	if _overlay == null or not _overlay.visible:
		return
	_overlay.visible = false
	get_tree().paused = false


func _finish_book() -> void:
	close_book()
	_play(_snd_end)
	# つぎに ひらくと ちがう おはなし(読み終えたときだけ すすむ)
	_story_i = (_story_i + 1) % STORIES.size()
	# 木が うれしそうに ぽよんと はずむ
	if _canopy:
		var tw := create_tween()
		tw.tween_property(_canopy, "scale", Vector3(1.12, 1.16, 1.12), 0.16).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_canopy, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _render_page() -> void:
	var story: Dictionary = STORIES[_story_i]
	var pages: Array = story["p"]
	_title_label.text = str(story["t"])
	_title_label.add_theme_color_override("font_color", story["c"])
	_body_label.text = str(pages[_page_i])
	var dots := ""
	for i in range(pages.size()):
		dots += ("●" if i == _page_i else "○") + ("  " if i < pages.size() - 1 else "")
	_dots_label.text = dots
	_next_btn.text = "おしまい!" if _page_i >= pages.size() - 1 else "つぎへ"


func _play(stream: AudioStreamWAV) -> void:
	if _sfx and stream:
		_sfx.stream = stream
		_sfx.play()


# === メッシュ / 音ヘルパー(instruments.gd と同じ作法)===

func _ball(radius: float, color: Color, rough: float) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	return _rim(MeshInstance3D.new(), s, color, rough)


func _box(sx: float, sy: float, sz: float, color: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return _rim(MeshInstance3D.new(), b, color, 0.7)


func _cyl(top_r: float, bottom_r: float, height: float, color: Color) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = height
	c.radial_segments = 14
	return _rim(MeshInstance3D.new(), c, color, 0.8)


func _rim(mi: MeshInstance3D, mesh: Mesh, color: Color, rough: float) -> MeshInstance3D:
	mi.mesh = mesh
	var sm := ShaderMaterial.new()
	sm.shader = RIM_SHADER
	sm.set_shader_parameter("albedo", color)
	sm.set_shader_parameter("roughness_val", rough)
	sm.set_shader_parameter("rim_color", Color(1, 1, 0.96))
	sm.set_shader_parameter("rim_power", 2.5)
	sm.set_shader_parameter("rim_strength", 0.5)
	mi.material_override = sm
	return mi


func _make_tone(freqs: Array, note_dur: float) -> AudioStreamWAV:
	var per: int = int(MIX_RATE * note_dur)
	var n: int = per * freqs.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for k in range(freqs.size()):
		var freq: float = float(freqs[k])
		for i in range(per):
			var t: float = float(i) / float(MIX_RATE)
			var prog: float = float(i) / float(per)
			var env: float = sin(prog * PI)
			var sv: float = sin(TAU * freq * t) * env * 0.45
			var v: int = int(clamp(sv, -1.0, 1.0) * 32767.0)
			data.encode_s16((k * per + i) * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
