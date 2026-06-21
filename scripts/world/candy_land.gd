extends Node3D

# おかしの きしゃで「おかしの くに」を 歩いて探索。Main 直下のノード。
# moon_trip / sky_castle / submarine と同じ「乗り物→別世界ワープ」骨格。
# ただし潜水艦の自動巡航とちがい、ここは 普通に歩いて まわる 甘い世界。
#
# 仕組み:
# - 地上(草原)に かわいい「おかしの きしゃ」(チョコの機関車)を駐車。
#   近づくと HUD `CandyButton`「おかしの くにへ いこう」。
# - 押すと フェード → 遠くの「おかしの くに」へ テレポート(歩ける床+落下防止)。
#   チョコの丘・ロリポップの木・クッキーの家・ゼリーの川・グミの どうぶつ・
#   わたあめの くも。あまいお菓子に近づくと「げんき アップ」、ほしも拾える。
# - くにに いる間は「おうちへ かえる」を常時表示。いつでも帰れる。
#
# 怖くない配慮(厳守): 明るいパステル・敵なし・失敗/落下なし(見えない壁+安全網)・
# ひらがな/カタカナ・大きいボタン・やさしい音。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const CANDY_DOCK := Vector2(44.0, -30.0)            # 地上の駐車(草原・他の乗り物と離す)
const CANDY_POS := Vector3(2000.0, 60.0, -2000.0)   # おかしの くに(遠く・床の上面が CANDY_POS.y)
const ENTER_RANGE := 10.0
const WorldRefs = preload("res://scripts/world/world_refs.gd")
const WorldConstants = preload("res://scripts/world/world_constants.gd")
const FADE_TIME := WorldConstants.FADE_TIME
const FLOOR_R := 120.0          # 歩ける床の半径
const WALL_R := 112.0           # 見えない壁(落ちない)
const GET_RANGE := 3.2          # お菓子/ほしの 近接獲得

const CANDY_SKY := Color(1.0, 0.86, 0.92)
const FLOOR_C := Color(1.0, 0.93, 0.86)
const FLOOR_DOT := Color(1.0, 0.78, 0.86)
const CHOC := Color(0.46, 0.29, 0.17)
const CHOC_DK := Color(0.36, 0.21, 0.12)
const ICING := Color(1.0, 0.98, 0.96)
const STICK_C := Color(0.96, 0.94, 0.88)
const CANDY_COLS := [Color(1.0, 0.6, 0.74), Color(0.62, 0.9, 0.78), Color(1.0, 0.86, 0.45), Color(0.74, 0.66, 0.96), Color(1.0, 0.72, 0.5), Color(0.6, 0.84, 1.0)]
const GUMMY_COLS := [Color(1.0, 0.5, 0.6, 0.8), Color(0.55, 0.85, 0.6, 0.8), Color(1.0, 0.8, 0.4, 0.8), Color(0.7, 0.6, 0.95, 0.8), Color(0.5, 0.8, 1.0, 0.8)]

var _player: CharacterBody3D
var _rig: Node
var _dn: Node
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _hud: Node
var _ride: Node
var _gs: Node
var _petals: GPUParticles3D
var _btn: BaseButton

var _on_candy: bool = false
var _busy: bool = false
var _world_built: bool = false
var _train_pos: Vector3 = Vector3.ZERO   # 地上の おかしの きしゃ(近接判定)
var _sweets: Array = []                  # [{node, base_y, phase, taken}] げんき
var _stars: Array = []                   # [{node, base_y, phase, taken}] ほし
var _gummies: Array = []                 # [{node, base_y, phase, spin}]
var _sfx: AudioStreamPlayer
var _btn_text: String = ""
var _earth_fog_density: float = 0.0009
var _earth_fog_enabled: bool = true


func _ready() -> void:
	var root := get_tree().root
	_player = WorldRefs.req(root, "Player", "Candy") as CharacterBody3D
	_rig = WorldRefs.req(root, "CameraRig", "Candy")
	_dn = WorldRefs.req(root, "DayNightCycle", "Candy")
	_env = WorldRefs.req(root, "WorldEnvironment", "Candy") as WorldEnvironment
	_sun = WorldRefs.req(root, "Sun", "Candy") as DirectionalLight3D
	_hud = WorldRefs.req(root, "TouchHUD", "Candy")
	_ride = WorldRefs.req(root, "RideController", "Candy")
	_gs = WorldRefs.req(root, "GameState", "Candy")
	_petals = root.find_child("CherryPetals", true, false) as GPUParticles3D
	_btn = root.find_child("CandyButton", true, false) as BaseButton
	if _btn:
		_btn.pressed.connect(_on_pressed)
		_btn.visible = false
	if _env and _env.environment:
		_earth_fog_density = _env.environment.fog_density
		_earth_fog_enabled = _env.environment.fog_enabled
	_ensure_audio()
	# おかしの くに(遠く)は初回ワープ時に作る。地上の きしゃは最初から(近接判定に要る)。
	_train_pos = _dock_pos()
	_candy_train(self, _train_pos, 0.0)


func _process(delta: float) -> void:
	if _player == null or _btn == null or _busy:
		return
	if _on_candy:
		_update_sweets(delta)
		_update_stars(delta)
		_update_gummies(delta)
		# 安全網: もし床より下に落ちたら 中央へ そっと戻す(落下=怖いを作らない)
		if _player.global_position.y < CANDY_POS.y - 8.0:
			_player.global_position = CANDY_POS + Vector3(0, 2.0, 0)
			_player.velocity = Vector3.ZERO
		_set_btn_state("おうちへ かえる")
	else:
		var riding: bool = _ride != null and _ride.has_method("is_riding") and _ride.is_riding()
		var near: bool = (not riding) and _player.global_position.distance_to(_train_pos) < ENTER_RANGE
		_set_btn_state("おかしの くにへ いこう" if near else "")


func _set_btn_state(want: String) -> void:
	if want == _btn_text:
		return
	_btn_text = want
	if want == "":
		_btn.visible = false
	else:
		_btn.text = want
		_btn.visible = true


func _hide_btn() -> void:
	_btn.visible = false
	_btn_text = ""


func _on_pressed() -> void:
	if _busy:
		return
	if _on_candy:
		_go_home()
		return
	if _ride != null and _ride.has_method("is_riding") and _ride.is_riding():
		return
	if _player.global_position.distance_to(_train_pos) < ENTER_RANGE:
		_go_candy()


# === 行く / 帰る ===

# おでかけメニューから 直接ワープ(おかしの きしゃの近くにいなくても)。
func warp_in() -> void:
	if _busy or _on_candy:
		return
	_go_candy()


func is_active() -> bool:
	return _on_candy


func _go_candy() -> void:
	_busy = true
	_hide_btn()
	if not _world_built:
		_build_candy_world()
		_world_built = true
	_transition(_arrive_candy_mid, _arrive_candy_done)


func _go_home() -> void:
	_busy = true
	_hide_btn()
	_transition(_arrive_home_mid, _arrive_home_done)


func _arrive_candy_mid() -> void:
	_on_candy = true
	_player.global_position = CANDY_POS + Vector3(0, 2.0, 0)
	_player.velocity = Vector3.ZERO
	_snap_cam()
	_apply_candy_env()
	if _gs and _gs.has_method("set_candy_visited"):
		_gs.set_candy_visited()


func _arrive_candy_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("おかしの くにへ!")
	_busy = false


func _arrive_home_mid() -> void:
	_on_candy = false
	var gy: float = TerrainHeight.compute_height(CANDY_DOCK.x + 3.0, CANDY_DOCK.y)
	_player.global_position = Vector3(CANDY_DOCK.x + 3.0, gy + 1.0, CANDY_DOCK.y)
	_player.velocity = Vector3.ZERO
	_snap_cam()
	_restore_earth_env()


func _arrive_home_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ただいま!")
	_busy = false


func _snap_cam() -> void:
	if _rig and _rig.has_method("snap_to_target"):
		_rig.snap_to_target()


# === 環境(おかしの くに / 地球) ===

func _apply_candy_env() -> void:
	if _dn:
		_dn.set("paused", true)
	_set_petals(false)
	if _env and _env.environment:
		var e := _env.environment
		e.background_color = CANDY_SKY
		e.ambient_light_color = Color(1.0, 0.95, 0.95)
		e.ambient_light_energy = 0.6            # 明るい(暗くしない=怖くない)。0.85→0.6 で白飛び防止・パステルの発色を保つ
		e.fog_enabled = true
		e.fog_density = 0.0016                   # ふんわり遠景(でも近くは よく見える)
		e.fog_light_color = Color(1.0, 0.88, 0.92)
	if _sun:
		_sun.rotation_degrees = Vector3(-62.0, 24.0, 0.0)
		_sun.light_color = Color(1.0, 0.95, 0.92)
		_sun.light_energy = 1.05


func _restore_earth_env() -> void:
	if _env and _env.environment:
		_env.environment.fog_density = _earth_fog_density
		_env.environment.fog_enabled = _earth_fog_enabled
	if _dn:
		_dn.set("paused", false)
		_dn.set("time_of_day", _dn.get("time_of_day"))  # 背景/環境光/fog色/太陽を地球用に再適用
	_set_petals(true)


func _set_petals(on: bool) -> void:
	if _petals:
		_petals.emitting = on
		_petals.visible = on


# === フェード遷移 ===

func _transition(midpoint: Callable, done: Callable) -> void:
	if _hud == null or not _hud.has_method("set_fade_alpha"):
		midpoint.call()
		if done.is_valid():
			done.call()
		return
	var tw := create_tween()
	tw.tween_method(Callable(_hud, "set_fade_alpha"), 0.0, 1.0, FADE_TIME)
	tw.tween_callback(midpoint)
	tw.tween_method(Callable(_hud, "set_fade_alpha"), 1.0, 0.0, FADE_TIME)
	if done.is_valid():
		tw.tween_callback(done)


# === 地上の おかしの きしゃ ===

func _dock_pos() -> Vector3:
	var gy: float = TerrainHeight.compute_height(CANDY_DOCK.x, CANDY_DOCK.y)
	return Vector3(CANDY_DOCK.x, gy, CANDY_DOCK.y)


# チョコの機関車(地上用・おかしの くにの飾り用に使い回す)。
func _candy_train(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var t := Node3D.new()
	parent.add_child(t)
	t.position = pos
	t.rotation.y = yaw
	# 車体(チョコ)
	_lbox(t, Vector3(3.0, 1.5, 1.8), Vector3(0, 1.0, 0), CHOC)
	_lbox(t, Vector3(1.6, 1.3, 1.7), Vector3(-1.0, 2.0, 0), CHOC_DK)   # 運転台(うしろ)
	# アイシングの屋根
	_lbox(t, Vector3(3.2, 0.25, 2.0), Vector3(0, 1.78, 0), ICING)
	_lbox(t, Vector3(1.7, 0.22, 1.8), Vector3(-1.0, 2.68, 0), ICING)
	# えんとつ + わたあめの けむり
	_lcyl(t, 0.28, 0.8, Vector3(1.0, 2.1, 0), CHOC_DK, 12)
	_lsphere(t, 0.55, Vector3(1.0, 2.9, 0), Color(1.0, 0.72, 0.85))
	_lsphere(t, 0.4, Vector3(1.25, 3.25, 0.15), Color(1.0, 0.82, 0.9))
	# まどぎわの ガムドロップ
	for i in range(5):
		var gc: Color = CANDY_COLS[i % CANDY_COLS.size()]
		_lsphere(t, 0.2, Vector3(-1.2 + float(i) * 0.6, 1.4, 0.92), gc)
	# 車輪(あめ・赤)
	for wx in [-1.0, 0.0, 1.0]:
		for sz in [-0.95, 0.95]:
			var w := _lcyl(t, 0.42, 0.22, Vector3(wx, 0.42, sz), Color(0.95, 0.42, 0.46), 14)
			w.rotation.x = PI * 0.5
	# 前の ライト(光る)
	_lemit(t, 0.22, Vector3(1.55, 1.0, 0), Color(1.0, 0.95, 0.6))
	return t


# === おかしの くに(遠く、初回のみ生成) ===

func _build_candy_world() -> void:
	var c := CANDY_POS
	_build_floor(c)
	_build_safety_wall(c)
	_build_hills(c)
	_build_lollipops(c)
	_build_cookie_houses(c)
	_build_jelly_river(c)
	_build_cupcakes(c)
	_build_candy_canes(c)
	_build_cotton_clouds(c)
	_build_gummies(c)
	_build_sweets(c)
	_build_stars(c)
	# 帰りの目印に おかしの きしゃ(飾り。ボタンはいつでも出る)
	_candy_train(self, c + Vector3(0, 0, 8), PI)


# 歩ける床(当たり判定つき)+ あまい色の ドット。
func _build_floor(c: Vector3) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = FLOOR_R
	shape.height = 2.0
	col.shape = shape
	body.add_child(col)
	body.position = c + Vector3(0, -1.0, 0)   # 上面が c.y
	add_child(body)
	# 見た目の床(クリーム)
	_lcyl(self, FLOOR_R, 0.6, c + Vector3(0, -0.3, 0), FLOOR_C, 48)
	# 床の スプリンクル(平たい ドット)
	for i in range(40):
		var a: float = float(i) * 2.39996      # 黄金角でばらつき
		var rr: float = sqrt(float(i) / 40.0) * (FLOOR_R - 10.0)
		var dot := _lcyl(self, 0.7, 0.12, c + Vector3(cos(a) * rr, 0.02, sin(a) * rr), FLOOR_DOT if i % 2 == 0 else CANDY_COLS[i % CANDY_COLS.size()], 10)
		dot.scale = Vector3(1.0, 1.0, 2.2)
		dot.rotation.y = a


# 見えない壁(落ちない・怖くない)。リング状に箱コリジョンを並べる。
func _build_safety_wall(c: Vector3) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = c
	var n: int = 32
	for i in range(n):
		var a: float = float(i) / float(n) * TAU
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var chord: float = TAU * WALL_R / float(n) * 1.3
		box.size = Vector3(chord, 14.0, 1.0)
		col.shape = box
		col.position = Vector3(cos(a) * WALL_R, 6.0, sin(a) * WALL_R)
		col.rotation.y = -a
		body.add_child(col)


func _build_hills(c: Vector3) -> void:
	for i in range(8):
		var a: float = float(i) / 8.0 * TAU + 0.4
		var rr: float = 60.0 + float(i % 3) * 18.0
		var hill := _lsphere(self, 12.0 + float(i % 4) * 4.0, c + Vector3(cos(a) * rr, -2.0, sin(a) * rr), CHOC if i % 2 == 0 else CHOC_DK)
		hill.scale = Vector3(1.0, 0.45, 1.0)
		# てっぺんに アイシング
		var ice := _lsphere(self, 10.0 + float(i % 4) * 3.5, c + Vector3(cos(a) * rr, -0.5, sin(a) * rr), ICING)
		ice.scale = Vector3(1.0, 0.18, 1.0)


# ロリポップの木(あめ棒+うずまきの あめ玉)。
func _build_lollipops(c: Vector3) -> void:
	for i in range(12):
		var a: float = float(i) / 12.0 * TAU + 0.2
		var rr: float = 16.0 + float(i % 5) * 6.0
		var base := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		var col: Color = CANDY_COLS[i % CANDY_COLS.size()]
		var h: float = 4.0 + float(i % 3) * 1.5
		_lcyl(self, 0.22, h, base + Vector3(0, h * 0.5, 0), STICK_C, 10)   # あめ棒(白)
		var head := _lsphere(self, 1.6 + float(i % 3) * 0.4, base + Vector3(0, h + 1.0, 0), col)  # あめ玉
		head.scale = Vector3(1.0, 1.0, 0.4)
		# うずまき(白い細い輪を 重ねる)
		_lcyl(self, 1.2, 0.14, base + Vector3(0, h + 1.0, -0.25), ICING, 16).scale = Vector3(1.0, 1.0, 1.0)


func _build_cookie_houses(c: Vector3) -> void:
	var spots: Array[Vector3] = [Vector3(28, 0, 10), Vector3(-26, 0, 16), Vector3(12, 0, -30), Vector3(-18, 0, -24), Vector3(34, 0, -8)]
	for i in range(spots.size()):
		var p := c + spots[i]
		var gy: float = 0.0
		# 本体(クッキー色)
		_lbox(self, Vector3(5.0, 3.2, 4.5), p + Vector3(0, 1.6, 0), Color(0.78, 0.55, 0.32))
		# アイシングの 三角屋根(つぶした コーン)
		var roof := _lcone(self, 3.8, 2.4, p + Vector3(0, 4.4, 0), ICING)
		roof.rotation.y = PI * 0.25
		# ドア(チョコ)
		_lbox(self, Vector3(1.2, 2.0, 0.2), p + Vector3(0, 1.0, 2.28), CHOC_DK)
		# まど(光る あめ)
		for sx in [-1.4, 1.4]:
			_lemit(self, 0.5, p + Vector3(sx, 1.9, 2.3), CANDY_COLS[i % CANDY_COLS.size()]).scale = Vector3(1.0, 1.2, 0.3)
		# 屋根の ガムドロップ
		for k in range(4):
			_lsphere(self, 0.35, p + Vector3(-1.5 + float(k) * 1.0, 4.0 + float(k % 2) * 0.3, 1.9), CANDY_COLS[(i + k) % CANDY_COLS.size()])


# ゼリーの川(半透明の 帯を つなげる)。
func _build_jelly_river(c: Vector3) -> void:
	var pts: Array[Vector3] = [Vector3(-46, 0, -40), Vector3(-30, 0, -20), Vector3(-10, 0, -6), Vector3(10, 0, 6), Vector3(30, 0, 22), Vector3(48, 0, 40)]
	for i in range(pts.size() - 1):
		var a := c + pts[i]
		var b := c + pts[i + 1]
		var mid := (a + b) * 0.5
		var seg := b - a
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4.5, 0.3, seg.length() + 1.0)
		mi.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.85, 0.95, 0.6)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.15
		m.metallic = 0.2
		mi.material_override = m
		mi.position = mid + Vector3(0, 0.08, 0)
		mi.look_at_from_position(mi.position, mi.position + seg, Vector3.UP)
		add_child(mi)


func _build_cupcakes(c: Vector3) -> void:
	for i in range(6):
		var a: float = float(i) / 6.0 * TAU + 1.0
		var rr: float = 22.0 + float(i % 3) * 8.0
		var base := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		var cup: Color = CANDY_COLS[i % CANDY_COLS.size()]
		# カップ(下が細い)
		var cupmesh := _lcyl(self, 1.6, 2.0, base + Vector3(0, 1.0, 0), cup, 16)
		cupmesh.scale = Vector3(1.0, 1.0, 1.0)
		# クリーム(白い 重ねた球で うずまき)
		for k in range(3):
			var rk: float = 1.6 - float(k) * 0.45
			_lsphere(self, rk, base + Vector3(0, 2.2 + float(k) * 0.7, 0), ICING)
		# さくらんぼ
		_lsphere(self, 0.4, base + Vector3(0, 4.5, 0), Color(0.95, 0.3, 0.4))


func _build_candy_canes(c: Vector3) -> void:
	for i in range(8):
		var a: float = float(i) / 8.0 * TAU
		var base := c + Vector3(cos(a) * (WALL_R - 8.0), 0.0, sin(a) * (WALL_R - 8.0))
		# 白い ポール + 赤い 輪(縞)
		_lcyl(self, 0.35, 8.0, base + Vector3(0, 4.0, 0), STICK_C, 10)
		for k in range(5):
			_lcyl(self, 0.38, 0.5, base + Vector3(0, 1.0 + float(k) * 1.6, 0), Color(0.95, 0.4, 0.45), 10)
		# 上の カーブ(玉で代用)
		_lsphere(self, 0.45, base + Vector3(0, 8.0, 0), Color(0.95, 0.4, 0.45))


func _build_cotton_clouds(c: Vector3) -> void:
	for i in range(10):
		var a: float = float(i) / 10.0 * TAU + 0.5
		var rr: float = 30.0 + float(i % 4) * 14.0
		var pink: bool = i % 2 == 0
		var col: Color = Color(1.0, 0.75, 0.86) if pink else Color(0.7, 0.85, 1.0)
		var base := c + Vector3(cos(a) * rr, 18.0 + float(i % 3) * 5.0, sin(a) * rr)
		for k in range(4):
			var off := Vector3(float(k) * 1.6 - 2.4, sin(float(k)) * 0.6, cos(float(k)) * 0.8)
			_lsphere(self, 1.8 - float(k % 2) * 0.3, base + off, col)


# グミの どうぶつ(半透明・ぷるぷる弾む くま)。
func _build_gummies(c: Vector3) -> void:
	var spots: Array[Vector3] = [Vector3(8, 0, 14), Vector3(-14, 0, 8), Vector3(18, 0, -6), Vector3(-8, 0, -16), Vector3(2, 0, 20), Vector3(-20, 0, -4)]
	for i in range(spots.size()):
		var p := c + spots[i] + Vector3(0, 0.8, 0)
		var col: Color = GUMMY_COLS[i % GUMMY_COLS.size()]
		var g := Node3D.new()
		add_child(g)
		g.position = p
		# 体
		var body := _lgummy(g, 0.9, Vector3.ZERO, col)
		body.scale = Vector3(0.9, 1.0, 0.8)
		# 頭
		_lgummy(g, 0.6, Vector3(0, 1.0, 0.1), col)
		# 耳
		for sx in [-0.4, 0.4]:
			_lgummy(g, 0.22, Vector3(sx, 1.55, 0.1), col)
		# 目(黒)
		for sx in [-0.22, 0.22]:
			_lemit(g, 0.08, Vector3(sx, 1.1, 0.6), Color(0.1, 0.1, 0.12))
		_gummies.append({"node": g, "base_y": p.y, "phase": float(i) * 0.9, "spin": (1.0 if i % 2 == 0 else -1.0) * 0.4})


func _update_gummies(delta: float) -> void:
	for gm in _gummies:
		var node: Node3D = gm["node"]
		gm["phase"] += delta * 2.2
		node.position.y = gm["base_y"] + absf(sin(gm["phase"])) * 0.5   # ぷるぷる弾む
		node.rotation.y += gm["spin"] * delta


# === あまいお菓子(げんき) ===

func _build_sweets(c: Vector3) -> void:
	# 床の上に ふわふわ浮く お菓子(マカロン/ドーナツ風)を 7 個
	var spots: Array[Vector3] = [Vector3(6, 0, 6), Vector3(-10, 0, 12), Vector3(16, 0, 0), Vector3(-16, 0, -10), Vector3(0, 0, -18), Vector3(22, 0, 14), Vector3(-22, 0, 4)]
	for i in range(spots.size()):
		var col: Color = CANDY_COLS[i % CANDY_COLS.size()]
		var p := c + spots[i] + Vector3(0, 1.4, 0)
		var node := Node3D.new()
		add_child(node)
		node.position = p
		if i % 2 == 0:
			# ドーナツ風(平たい トーラスもどき: 球を つぶす + 穴っぽい 上掛け)
			var d := _lsphere(node, 0.7, Vector3.ZERO, col)
			d.scale = Vector3(1.0, 0.5, 1.0)
			_lsphere(node, 0.45, Vector3(0, 0.18, 0), ICING).scale = Vector3(1.0, 0.4, 1.0)
		else:
			# マカロン(2枚+クリーム)
			_lsphere(node, 0.6, Vector3(0, 0.25, 0), col).scale = Vector3(1.0, 0.45, 1.0)
			_lsphere(node, 0.6, Vector3(0, -0.25, 0), col).scale = Vector3(1.0, 0.45, 1.0)
			_lsphere(node, 0.5, Vector3.ZERO, ICING).scale = Vector3(1.0, 0.3, 1.0)
		_sweets.append({"node": node, "base_y": p.y, "phase": float(i) * 0.8, "taken": false})


func _update_sweets(delta: float) -> void:
	var pp: Vector3 = _player.global_position
	for sw in _sweets:
		if sw["taken"]:
			continue
		var node: Node3D = sw["node"]
		node.rotate_y(1.2 * delta)
		sw["phase"] += delta * 1.6
		node.position.y = sw["base_y"] + sin(sw["phase"]) * 0.22
		if node.global_position.distance_to(pp) < GET_RANGE:
			_collect_sweet(sw)


func _collect_sweet(sw: Dictionary) -> void:
	sw["taken"] = true
	var node: Node3D = sw["node"]
	_spawn_burst(node.global_position, Color(1.0, 0.7, 0.82))
	if _gs and _gs.has_method("add_energy"):
		_gs.add_energy(1)
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("おかし もぐもぐ! げんき アップ!")
	if _player and _player.has_method("celebrate"):
		_player.celebrate()
	if _sfx:
		_sfx.play()
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 1.6, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ZERO, 0.28)
	tw.tween_callback(node.queue_free)


# === ほし(ごほうび) ===

func _build_stars(c: Vector3) -> void:
	var spots: Array[Vector3] = [Vector3(-6, 0, -8), Vector3(14, 0, 10), Vector3(-18, 0, 2), Vector3(8, 0, -22), Vector3(24, 0, -2)]
	for i in range(spots.size()):
		var p := c + spots[i] + Vector3(0, 2.0, 0)
		var mi := _lemit(self, 0.5, p, Color(1.0, 0.92, 0.45))
		mi.scale = Vector3(1.0, 1.0, 0.5)
		_stars.append({"node": mi, "base_y": p.y, "phase": float(i) * 1.1, "taken": false})


func _update_stars(delta: float) -> void:
	var pp: Vector3 = _player.global_position
	for st in _stars:
		if st["taken"]:
			continue
		var node: Node3D = st["node"]
		node.rotate_y(1.0 * delta)
		st["phase"] += delta * 1.4
		node.position.y = st["base_y"] + sin(st["phase"]) * 0.25
		if node.global_position.distance_to(pp) < GET_RANGE:
			_collect_star(st)


func _collect_star(st: Dictionary) -> void:
	st["taken"] = true
	var node: Node3D = st["node"]
	_spawn_burst(node.global_position, Color(1.0, 0.92, 0.5))
	if _gs and _gs.has_method("add_star"):
		_gs.add_star()
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ほし ゲット!")
	if _player and _player.has_method("celebrate"):
		_player.celebrate()
	if _sfx:
		_sfx.play()
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.7, 1.7, 0.8), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ZERO, 0.28)
	tw.tween_callback(node.queue_free)


# === キラキラ ===

func _spawn_burst(pos: Vector3, color: Color) -> void:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, -1.2, 0)
	pm.scale_min = 0.15
	pm.scale_max = 0.4
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.34, 0.34)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


# === 音 ===

func _ensure_audio() -> void:
	if _sfx == null:
		_sfx = AudioStreamPlayer.new()
		_sfx.stream = _make_tone(880.0, 1318.0, 0.2)   # やさしい きらきら音
		_sfx.volume_db = -5.0
		add_child(_sfx)


func _make_tone(freq_a: float, freq_b: float, dur: float) -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / float(rate)
		var prog: float = float(i) / float(n)
		var freq: float = freq_a if prog < 0.5 else freq_b
		var env: float = sin(prog * PI)
		var s: float = sin(TAU * freq * t) * env * 0.5
		data.encode_s16(i * 2, int(clamp(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


# === メッシュ ヘルパー(parent を渡す) ===

func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.05
	return m


func _lbox(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(color, 0.6)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _lcyl(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, segs: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	mi.mesh = c
	mi.material_override = _mat(color, 0.7)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _lcone(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 14
	mi.mesh = c
	mi.material_override = _mat(color, 0.6)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _lsphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	mi.material_override = _mat(color, 0.7)
	mi.position = pos
	parent.add_child(mi)
	return mi


# 半透明の グミ(ぷるんとした 見た目)。
func _lgummy(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	m.metallic = 0.3
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _lemit(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.7
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi
