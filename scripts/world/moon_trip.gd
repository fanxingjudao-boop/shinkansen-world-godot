extends Node3D

# 月(つき)への旅行。Main 直下のノード。
#
# 仕組み:
# - 地球(いつもの世界)に「ロケットの発射台」を建てる。プレイヤーが近づくと
#   HUD に「つきへ いく」ボタンが出る。押すとフェードして月へワープ。
# - 月は遠く(MOON_POS)に作った大きな球体。上はゆるやかなドームで歩ける。
#   背景を宇宙の黒にし、大きな地球と星、もちつきする つきのうさぎを置く。
#   重力を弱く(ふわっと跳べる)する。
# - 月にもロケットを建て、近づくと「おうちへ かえる」ボタンで地球に戻れる。
#   失敗概念なし・いつでも帰れる。
#
# 怖くない配慮: 大きな球体なので上は平らに近く落ちる感じがない、真っ暗にしすぎない
# (環境光は残す)、急に動かない(フェード)、ふちに見えない壁 + 落ちても自動で戻す。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const LAUNCH_POS := Vector2(26.0, 22.0)        # 地球の発射台(プレイヤー初期 (0,0,0) の近く)
const MOON_POS := Vector3(2000.0, 60.0, 2000.0) # 月のてっぺん(球の中心は この真下 PLANET_R ぶん)
const PLANET_R := 22.0                          # 月=小さな惑星の半径。裏側まで ぐるっと歩ける大きさ
const ENTER_RANGE := 8.5                        # ロケットにこの距離で「つきへ いく」が出る
const MOON_GRAVITY := 0.42                      # 惑星の重力倍率(ふわっと跳べるが 跳びすぎない)
const FADE_TIME := 0.35
const DANGO_GET_RANGE := 2.8                    # もちだんごに近づくと獲得
const BUGGY_RANGE := 4.5                        # 月面カーに近づくと「のる」
const BUGGY_SPEED_SCALE := 1.8                  # 月面カーに のると はやく走れる

const MOON_GRAY := Color(0.72, 0.72, 0.76)
const MOON_GRAY_DK := Color(0.58, 0.58, 0.63)
const ROCKET_WHITE := Color(0.95, 0.95, 0.97)
const ROCKET_RED := Color(0.95, 0.35, 0.4)
const WINDOW_C := Color(0.55, 0.85, 1.0)
const SPACE_BG := Color(0.03, 0.02, 0.08)
const EARTH_BLUE := Color(0.3, 0.55, 0.9)
const EARTH_GREEN := Color(0.45, 0.78, 0.5)

var _player: CharacterBody3D
var _rig: Node
var _dn: Node
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _hud: Node
var _btn: BaseButton
var _ride: Node   # RideController(乗車中は月ボタンを出さない・押させない)
var _gs: Node     # GameState(月に行った記録=ミッション用)
var _petals: GPUParticles3D  # さくらふぶき(地球の演出。月では止める)

var _on_moon: bool = false
var _busy: bool = false
var _rocket_pos: Vector3 = Vector3.ZERO        # 地球のロケット(つきへ いく)
var _moon_rocket_pos: Vector3 = Vector3.ZERO   # 月のロケット(おうちへ かえる)
var _moon_built: bool = false   # 月は初回ワープ時に組み立てる(起動時のノード/メモリ節約)

# 月の追加要素
var _earth_node: Node3D         # ゆっくり回る地球(宇宙の演出)
var _ufo: Node3D                # ふわふわ漂う UFO
var _dango: Array = []          # もちだんご [{node, base_y, phase, taken}]
var _buggy: Node3D              # 月面カー(駐車中は self の子)
var _buggy_mounted: bool = false
var _buggy_pos: Vector3 = Vector3.ZERO   # 駐車位置(のる の近接判定用)
var _sfx: AudioStreamPlayer     # もちだんご獲得音(一発)
var _engine: AudioStreamPlayer  # 月面カーのエンジン音(ループ)
var _moon_btn_text: String = "" # 月でのボタン表示テキスト(変化時だけ更新)


func _ready() -> void:
	var root := get_tree().root
	_player = root.find_child("Player", true, false) as CharacterBody3D
	_rig = root.find_child("CameraRig", true, false)
	_dn = root.find_child("DayNightCycle", true, false)
	_env = root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	_sun = root.find_child("Sun", true, false) as DirectionalLight3D
	_hud = root.find_child("TouchHUD", true, false)
	_ride = root.find_child("RideController", true, false)
	_gs = root.find_child("GameState", true, false)
	_petals = root.find_child("CherryPetals", true, false) as GPUParticles3D
	_btn = root.find_child("MoonButton", true, false) as BaseButton
	if _btn:
		_btn.pressed.connect(_on_pressed)
		_btn.visible = false
	# 月本体は重い(星40・縁36・地球・うさぎ等)ので起動時には作らず、初回ワープ時に作る。
	# 発射台(地球側)は近接判定に必要なので最初から作る。
	_build_launch_pad()


func _process(_delta: float) -> void:
	if _player == null or _btn == null or _busy:
		return
	if _on_moon:
		var center := _planet_center()
		# カメラの「上」を いまの足元の球面法線に合わせる(裏側でも頭が上=酔いにくい)
		var up: Vector3 = (_player.global_position - center).normalized()
		if _rig and _rig.has_method("set_surface_up"):
			_rig.set_surface_up(up)
		# 安全網: 万一 はるか遠くへ飛んでいったら てっぺんへ戻す(宇宙に消えない)
		if _player.global_position.distance_to(center) > PLANET_R * 4.0:
			if _buggy_mounted:
				_dismount_buggy()
			_player.global_position = center + Vector3(0, PLANET_R + 3.0, 0)
			_player.velocity = Vector3.ZERO
		# 宇宙の演出: 地球をゆっくり回す + UFO をゆっくり旋回
		if _earth_node:
			_earth_node.rotate_y(_delta * 0.06)
		if _ufo:
			_ufo.rotate_y(_delta * 0.35)
		# もちだんごの 浮遊・回転・獲得
		_update_dango(_delta)
		# ボタンの文脈分岐(乗車中→おりる / カー近い→のる / ロケット近い→かえる)
		_update_moon_button()
	else:
		# 乗車中はロケットに乗れないので月ボタンを出さない(状態崩壊の防止)
		var riding: bool = _ride != null and _ride.has_method("is_riding") and _ride.is_riding()
		var near: bool = (not riding) and _player.global_position.distance_to(_rocket_pos) < ENTER_RANGE
		if near and not _btn.visible:
			_set_btn("つきへ いく")
		elif not near and _btn.visible:
			_btn.visible = false


func _set_btn(text: String) -> void:
	_btn.text = text
	_btn.visible = true


func _on_pressed() -> void:
	if _busy:
		return
	if _on_moon:
		# 文脈で分岐: 乗車中→おりる / カー近い→のる / ロケット近い→おうちへ かえる
		if _buggy_mounted:
			_dismount_buggy()
			return
		if _buggy and _player.global_position.distance_to(_buggy_pos) < BUGGY_RANGE:
			_mount_buggy()
			return
		if _player.global_position.distance_to(_moon_rocket_pos) < ENTER_RANGE:
			_go_home()
		return
	# 乗車中は月へ行かない(状態崩壊の防止)
	if _ride != null and _ride.has_method("is_riding") and _ride.is_riding():
		return
	if _player.global_position.distance_to(_rocket_pos) < ENTER_RANGE:
		_go_moon()


# === 月へ / 地球へ ===

func _go_moon() -> void:
	_busy = true
	_btn.visible = false
	# 初回だけ月を組み立てる(フェード中なので見えない)
	if not _moon_built:
		_build_moon()
		_moon_built = true
	_transition(func() -> void:
		_on_moon = true
		var center := _planet_center()
		_player.global_position = center + Vector3(0, PLANET_R + 3.0, 0)  # てっぺんの上に着地
		_player.velocity = Vector3.ZERO
		_player.set("planet_center", center)
		_player.set("planet_mode", true)   # 球中心へ重力・up=法線(裏側まで歩ける)
		_player.set("gravity_scale", MOON_GRAVITY)
		_player.up_direction = Vector3.UP  # てっぺんでは 法線=UP
		if _rig and _rig.has_method("set_surface_up"):
			_rig.set_surface_up(Vector3.UP)
		_snap_cam()
		_apply_moon_env()
		if _gs and _gs.has_method("set_moon_visited"):
			_gs.set_moon_visited()  # ミッション「ロケットで つきへ いこう」
	, func() -> void:
		if _hud and _hud.has_method("show_notice"):
			_hud.show_notice("つきに とうちゃく!")
		_busy = false)


func _go_home() -> void:
	_busy = true
	if _buggy_mounted:
		_dismount_buggy()  # 念のため(降車UIからは来ないが状態を清算)
	_btn.visible = false
	_moon_btn_text = ""
	var gy: float = TerrainHeight.compute_height(LAUNCH_POS.x + 4.0, LAUNCH_POS.y) + 1.5
	var home := Vector3(LAUNCH_POS.x + 4.0, gy, LAUNCH_POS.y)
	_transition(func() -> void:
		_on_moon = false
		_player.set("planet_mode", false)   # 通常の Y 重力へ戻す
		_player.global_position = home
		_player.velocity = Vector3.ZERO
		_player.set("gravity_scale", 1.0)
		_player.up_direction = Vector3.UP
		_player.rotation = Vector3.ZERO     # 球面で傾けた姿勢を まっすぐに戻す
		if _rig and _rig.has_method("set_surface_up"):
			_rig.set_surface_up(Vector3.UP)
		_snap_cam()
		_restore_earth_env()
	, func() -> void:
		if _hud and _hud.has_method("show_notice"):
			_hud.show_notice("ただいま!")
		_busy = false)


func _snap_cam() -> void:
	if _rig and _rig.has_method("snap_to_target"):
		_rig.snap_to_target()


# 月の空(宇宙)に切り替え。DayNightCycle を止めて手動で環境を設定。
func _apply_moon_env() -> void:
	if _dn:
		_dn.set("paused", true)
	_set_petals(false)  # 月では さくらふぶき を止める(宇宙に桜は不要)
	if _env and _env.environment:
		var e := _env.environment
		e.background_color = SPACE_BG
		e.ambient_light_color = Color(0.55, 0.55, 0.66)
		e.ambient_light_energy = 0.55
		e.fog_light_color = SPACE_BG
	if _sun:
		_sun.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
		_sun.light_color = Color(1.0, 1.0, 0.96)
		_sun.light_energy = 0.7


# 地球の空に戻す。DayNightCycle を再開し、すぐ反映させる。
func _restore_earth_env() -> void:
	if _dn:
		_dn.set("paused", false)
		# 時刻の setter を再トリガーして即座に空・太陽を地球用へ戻す
		_dn.set("time_of_day", _dn.get("time_of_day"))
	_set_petals(true)  # 地球に戻ったら さくらふぶき を再開


func _set_petals(on: bool) -> void:
	if _petals:
		_petals.emitting = on
		_petals.visible = on


# === フェード遷移(TouchHUD の Fade を駆動) ===

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


# === 発射台 + ロケット(地球) ===

func _build_launch_pad() -> void:
	var gy: float = TerrainHeight.compute_height(LAUNCH_POS.x, LAUNCH_POS.y)
	_rocket_pos = _build_rocket(Vector3(LAUNCH_POS.x, gy, LAUNCH_POS.y))


# 発射台 + ロケットを base(地面の点)に建て、ロケットの中心位置を返す。
# 地球(発射)・月(帰還)で共用。
func _build_rocket(base: Vector3) -> Vector3:
	# 発射台(灰色の円盤)
	_cyl(3.2, 0.5, base + Vector3(0, 0.25, 0), MOON_GRAY_DK, 14)
	# ロケット本体(白い円柱)
	var body_y: float = base.y + 0.5
	_cyl(0.95, 4.2, Vector3(base.x, body_y + 2.1, base.z), ROCKET_WHITE, 16)
	# 赤い帯
	_cyl(1.0, 0.4, Vector3(base.x, body_y + 3.4, base.z), ROCKET_RED, 16)
	# ノーズ(赤い円錐)
	_cone(0.95, 1.7, Vector3(base.x, body_y + 4.2 + 0.85, base.z), ROCKET_RED)
	# 窓(水色、光る)
	_emit_sphere(0.34, Vector3(base.x, body_y + 2.7, base.z - 0.9), WINDOW_C)
	# フィン(3枚、赤)
	for k in range(3):
		var a: float = float(k) / 3.0 * TAU
		var fx: float = base.x + cos(a) * 0.95
		var fz: float = base.z + sin(a) * 0.95
		var fin := _box(Vector3(0.12, 1.3, 0.9), Vector3(fx, body_y + 0.7, fz), ROCKET_RED, 0.6)
		fin.rotation.y = -a
	# 噴射口(下の灰色)
	_cyl(0.7, 0.4, Vector3(base.x, body_y + 0.1, base.z), MOON_GRAY_DK, 12)
	return Vector3(base.x, body_y + 2.0, base.z)


# === 月(遠くの宇宙) ===

func _build_moon() -> void:
	# 月=小さな惑星。1つの球(+球コリジョン)で、重力が中心へ向くので 裏側まで歩ける。
	# ふちの壁は不要(球なので そもそも「ふち」が無い)。
	var center := _planet_center()
	_sphere(PLANET_R, center, MOON_GRAY, 0.9)
	_add_sphere_collision(PLANET_R, center)
	# クレーター(全周に散らす)。各点の法線に合わせて 少し埋め込む。
	var crater_dirs := [
		Vector3(0.3, 0.9, 0.2), Vector3(-0.5, 0.6, 0.4), Vector3(0.6, 0.2, -0.5),
		Vector3(-0.3, -0.4, 0.7), Vector3(0.2, -0.85, -0.3), Vector3(-0.7, -0.2, -0.5),
		Vector3(0.8, -0.1, 0.3), Vector3(-0.2, 0.35, -0.9), Vector3(0.45, -0.55, 0.55),
	]
	for d in crater_dirs:
		_place_on_planet(_crater_node(), d, -0.15)
	# 宇宙(惑星のまわり): 大きな地球(回る)・星・UFO
	_build_earth_in_sky()
	_build_stars()
	_build_ufo()
	# ロケット(てっぺん=法線が UP なので そのまま建つ)。これで おうちへ かえる。
	_moon_rocket_pos = _build_rocket(center + Vector3(0, PLANET_R, 0))
	# もちつき + もちだんご(てっぺん近く、法線に合わせて立てる)
	var mochi_dir := Vector3(0.32, 1.0, -0.5).normalized()
	_build_mochi_pounding(mochi_dir)
	_build_mochidango(mochi_dir)
	# 月面カー(横のほう。歩いて行く目標になる)
	_build_moon_buggy(Vector3(1.0, 0.45, 0.25).normalized())
	# 音(もちだんご獲得・月面カーのエンジン)
	_ensure_audio()


# 球の中心(MOON_POS の真下 PLANET_R)。
func _planet_center() -> Vector3:
	return MOON_POS + Vector3(0, -PLANET_R, 0)


# up(球面法線)を +Y とする向きの Basis。装飾を球面に立てるのに使う。
func _surface_basis(up: Vector3) -> Basis:
	var u := up.normalized()
	var ref := Vector3.FORWARD
	var x := u.cross(ref)
	if x.length() < 0.01:
		x = u.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(u).normalized()
	return Basis(x, u, z)


# ノードを 球面上(中心から dir 方向、半径+lift)に置き、法線に合わせて傾ける。
func _place_on_planet(node: Node3D, dir: Vector3, lift: float) -> void:
	var d := dir.normalized()
	var pos := _planet_center() + d * (PLANET_R + lift)
	node.transform = Transform3D(_surface_basis(d), pos)


# クレーター(へこんだ濃い灰の薄い円盤)。Y軸が法線になるよう置く。
func _crater_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 2.4
	c.bottom_radius = 2.9
	c.height = 0.5
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = _mat(MOON_GRAY_DK, 0.85)
	add_child(mi)
	return mi


func _build_earth_in_sky() -> void:
	var pos := MOON_POS + Vector3(-70, 120, -220)
	# 地球+大陸を1つの Node3D にまとめ、_process でゆっくり回す
	_earth_node = Node3D.new()
	_earth_node.position = pos
	add_child(_earth_node)
	_local_emit(_earth_node, 42.0, Vector3.ZERO, EARTH_BLUE)
	# 大陸(緑)を球の表面ぺたぺた(回転で見え隠れする)
	var conts := [Vector3(10, 14, -38), Vector3(-18, -6, -38), Vector3(20, -16, -34), Vector3(-8, 22, -34), Vector3(34, 6, 18), Vector3(-30, -14, 22)]
	for c in conts:
		_local_emit(_earth_node, 8.0, c, EARTH_GREEN)


func _build_stars() -> void:
	# 月のまわりのドーム状に小さな光る点を散らす(seed 固定で毎回同じ)
	seed(7777)
	for i in range(40):
		var a: float = randf() * TAU
		var el: float = randf_range(0.1, 1.2)
		var r: float = randf_range(120.0, 260.0)
		var p := MOON_POS + Vector3(cos(a) * r, 40.0 + sin(el) * r * 0.8, sin(a) * r)
		_emit_sphere(randf_range(0.8, 1.8), p, Color(1, 1, 0.95))


# 白くてまるい「つきのうさぎ」(体 + 長い耳 + 目)。root を返す。
# arms=true で前に のばした うで(もちつきの 手)を付ける。
# parent を渡すと その子に作る(惑星のもちつきは 傾いた root の下に作るため)。
func _build_moon_bunny(pos: Vector3, face_yaw: float, arms: bool = false, parent: Node3D = null) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = face_yaw
	var par: Node3D = parent if parent != null else self
	par.add_child(root)
	var white := Color(0.97, 0.97, 0.98)
	# 体
	var body := _local_sphere(root, 0.6, Vector3(0, 0.6, 0), white)
	body.scale = Vector3(1.0, 1.1, 1.0)
	# 頭
	_local_sphere(root, 0.42, Vector3(0, 1.35, 0), white)
	# 耳(2本)
	for sx in [-1.0, 1.0]:
		var ear := _local_capsule(root, 0.12, 0.7, Vector3(sx * 0.16, 1.9, 0), white)
		ear.rotation.z = sx * 0.18
	# うで(前にのばす。もちつきの手)
	if arms:
		for sx in [-1.0, 1.0]:
			var arm := _local_capsule(root, 0.1, 0.5, Vector3(sx * 0.45, 0.95, -0.3), white)
			arm.rotation.x = -0.7
	# 目(黒、光らない)
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.07
		es.height = 0.14
		eye.mesh = es
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.1, 0.12)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		eye.material_override = m
		eye.position = Vector3(sx * 0.16, 1.4, -0.36)
		root.add_child(eye)
	return root


# つきの もちつき: うす + おもち + きねを ふりおろす うさぎ(つき手)+ 返し手のうさぎ。
# dir(球面の方向)に 法線へ合わせた root を立て、その下に local で組む(惑星のどこでも まっすぐ立つ)。
func _build_mochi_pounding(dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	_place_on_planet(root, dir, 0.0)
	var wood := Color(0.5, 0.34, 0.24)
	var wood_dk := Color(0.4, 0.27, 0.19)
	# うす(もちを つく うつわ)
	_local_cyl(root, 0.75, 0.7, Vector3(0, 0.35, 0), wood, 18)
	_local_cyl(root, 0.6, 0.18, Vector3(0, 0.72, 0), wood_dk, 18)   # ふちの内がわの影
	# おもち(しろくて まるい・ひらたい)
	var mochi := _local_sphere(root, 0.5, Vector3(0, 0.8, 0), Color(0.99, 0.99, 1.0))
	mochi.scale = Vector3(1.0, 0.45, 1.0)
	# つき手のうさぎ(うすの方=-z を向く。うでを のばす)
	_build_moon_bunny(Vector3(0, 0.0, 1.5), 0.0, true, root)
	# 返し手のうさぎ(-z がわで しゃがんで もちを かえす。小さく ぴょこぴょこ)
	var flipper := _build_moon_bunny(Vector3(0, 0.0, -1.35), PI, true, root)
	flipper.scale = Vector3.ONE * 0.8
	var ft := create_tween().set_loops()
	ft.tween_property(flipper, "position:y", 0.14, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ft.tween_property(flipper, "position:y", 0.0, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# きね(え + あたま)を ピボットの子にして 上下に ふる(root の local)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 2.0, 0.4)
	pivot.rotation.x = -1.15
	root.add_child(pivot)
	_local_cyl(pivot, 0.07, 1.4, Vector3(0, -0.7, 0), wood, 8)        # え
	_local_cyl(pivot, 0.2, 0.45, Vector3(0, -1.45, 0), Color(0.85, 0.7, 0.5), 12)  # あたま
	# つく うごき: ふりおろす(はやい)→ もちあげる(ゆっくり)→ すこし まつ
	var kt := create_tween().set_loops()
	kt.tween_property(pivot, "rotation:x", 0.1, 0.28) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	kt.tween_property(pivot, "rotation:x", -1.15, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	kt.tween_interval(0.25)


# === もちだんご(近づくと げんき+1) ===

# もちつき(dir 方向)の まわりに 三色だんごを 数本、球面に立てて 少し浮かせて置く。
func _build_mochidango(dir: Vector3) -> void:
	var b := _surface_basis(dir)   # b.x / b.z = 接平面、b.y = 法線
	var offs := [Vector2(2.4, 0.6), Vector2(-2.2, 1.2), Vector2(1.4, -2.0), Vector2(-1.6, -1.6), Vector2(3.0, -0.8)]
	for i in range(offs.size()):
		var o: Vector2 = offs[i]
		var ddir: Vector3 = (dir.normalized() * PLANET_R + b.x * o.x + b.z * o.y).normalized()
		var node := _make_dango()
		add_child(node)
		_place_on_planet(node, ddir, 1.0)   # 1m 浮かせる(法線に沿って)
		_dango.append({"node": node, "base_pos": node.global_position, "normal": ddir, "phase": float(i) * 1.3, "taken": false})


# 三色だんご(くし + ピンク・白・みどりの3だんご)。
func _make_dango() -> Node3D:
	var root := Node3D.new()
	_local_cyl(root, 0.04, 0.95, Vector3(0, 0.18, 0), Color(0.82, 0.62, 0.42), 6)
	_local_sphere(root, 0.17, Vector3(0, 0.12, 0), Color(1.0, 0.7, 0.8))
	_local_sphere(root, 0.17, Vector3(0, 0.34, 0), Color(1.0, 0.99, 0.96))
	_local_sphere(root, 0.17, Vector3(0, 0.56, 0), Color(0.7, 0.9, 0.6))
	return root


# もちだんごを 浮遊(法線方向)・回転(自分の up まわり)させ、近づいたら獲得。
func _update_dango(delta: float) -> void:
	if _dango.is_empty():
		return
	var pp: Vector3 = _player.global_position
	for dd in _dango:
		if dd["taken"]:
			continue
		var node: Node3D = dd["node"]
		node.rotate_object_local(Vector3.UP, 1.4 * delta)
		dd["phase"] += delta * 1.6
		node.global_position = dd["base_pos"] + dd["normal"] * (sin(dd["phase"]) * 0.22)
		if node.global_position.distance_to(pp) < DANGO_GET_RANGE:
			_collect_dango(dd)


func _collect_dango(dd: Dictionary) -> void:
	dd["taken"] = true
	var node: Node3D = dd["node"]
	_spawn_burst(node.global_position, Color(1.0, 0.7, 0.8))
	if _gs and _gs.has_method("add_energy"):
		_gs.add_energy(1)  # げんき+1(公平に良い結果)
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("もちだんご ゲット!")
	if _player and _player.has_method("celebrate"):
		_player.celebrate()
	if _sfx:
		_sfx.play()
	var fly_to: Vector3 = dd["base_pos"] + dd["normal"] * 2.0  # 法線方向へ ふわっと上がって消える
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 1.6, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ZERO, 0.28)
	tw.parallel().tween_property(node, "global_position", fly_to, 0.28)
	tw.tween_callback(node.queue_free)


# 獲得時に キラキラを 一発はじけさせる(GPUParticles one-shot、寿命後 自動削除)。
func _spawn_burst(pos: Vector3, color: Color) -> void:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 3.6
	pm.gravity = Vector3(0, -2.0, 0)  # 月は低重力ぎみ
	pm.scale_min = 0.15
	pm.scale_max = 0.35
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.32, 0.32)
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


# === UFO(ふわふわ漂う) ===

func _build_ufo() -> void:
	_ufo = Node3D.new()
	_ufo.position = MOON_POS + Vector3(-20, 15, 12)
	add_child(_ufo)
	var saucer := _local_sphere(_ufo, 2.2, Vector3.ZERO, Color(0.82, 0.85, 0.92))
	saucer.scale = Vector3(1.0, 0.34, 1.0)
	var ring := _local_sphere(_ufo, 2.45, Vector3(0, -0.08, 0), Color(0.7, 0.74, 0.82))
	ring.scale = Vector3(1.0, 0.12, 1.0)
	var dome := _local_emit(_ufo, 1.1, Vector3(0, 0.55, 0), WINDOW_C)
	dome.scale = Vector3(1.0, 0.8, 1.0)
	# 下の あかり(3つ、ふわっと光る)
	for k in range(3):
		var a: float = float(k) / 3.0 * TAU
		_local_emit(_ufo, 0.22, Vector3(cos(a) * 1.4, -0.5, sin(a) * 1.4), Color(1.0, 0.85, 0.5))
	# ふわふわ上下(ループ)。回転は _process で。
	var base_y: float = _ufo.position.y
	var tw := create_tween().set_loops()
	tw.tween_property(_ufo, "position:y", base_y + 2.5, 2.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_ufo, "position:y", base_y, 2.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# === 月面カー(のって 月を はしる) ===

func _build_moon_buggy(dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	_place_on_planet(root, dir, 0.0)   # 球面に立てる(法線に合わせる)
	var body_c := Color(1.0, 0.7, 0.4)     # かわいいオレンジ
	var seat_c := Color(0.92, 0.6, 0.34)
	var wheel_c := Color(0.32, 0.32, 0.36)
	# 車体(低い箱)+ 座面
	_local_box(root, Vector3(2.0, 0.5, 1.3), Vector3(0, 0.55, 0), body_c)
	_local_box(root, Vector3(1.0, 0.22, 1.0), Vector3(0.35, 0.85, 0), seat_c)
	# キャノピー(水色の ドーム)
	var canopy := _local_emit(root, 0.55, Vector3(-0.45, 1.1, 0), WINDOW_C)
	canopy.scale = Vector3(1.3, 0.9, 1.0)
	# アンテナ + 先の あかり
	_local_cyl(root, 0.04, 0.9, Vector3(-0.85, 1.35, 0.45), Color(0.8, 0.8, 0.85), 6)
	_local_emit(root, 0.12, Vector3(-0.85, 1.85, 0.45), Color(1.0, 0.5, 0.5))
	# タイヤ4輪(横向き円柱)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := _local_cyl(root, 0.36, 0.3, Vector3(sx * 0.72, 0.36, sz * 0.62), wheel_c, 12)
			w.rotation.z = PI * 0.5
	_buggy = root
	_buggy_pos = root.global_position


# 月面カーに のる: バギーを プレイヤーの子にして 一緒に動く + はやくなる + エンジン音。
func _mount_buggy() -> void:
	if _buggy == null or _buggy_mounted:
		return
	_buggy_mounted = true
	if _buggy.get_parent():
		_buggy.get_parent().remove_child(_buggy)
	_player.add_child(_buggy)
	_buggy.position = Vector3(0, -0.35, 0)
	_buggy.rotation = Vector3.ZERO
	_player.set("speed_scale", BUGGY_SPEED_SCALE)
	if _engine:
		_engine.play()
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("カーに のったよ!")


# 月面カーから おりる: バギーを いまの足元(球面)に 置き直して(駐車)、速度を もどす。
func _dismount_buggy() -> void:
	if not _buggy_mounted:
		return
	_buggy_mounted = false
	var wp: Vector3 = _buggy.global_position
	if _buggy.get_parent():
		_buggy.get_parent().remove_child(_buggy)
	add_child(_buggy)
	var dir: Vector3 = (wp - _planet_center()).normalized()
	_place_on_planet(_buggy, dir, 0.0)
	_buggy_pos = _buggy.global_position
	_player.set("speed_scale", 1.0)
	if _engine:
		_engine.stop()


# 月でのボタン文脈分岐(変化したときだけ更新してチラつき防止)。
func _update_moon_button() -> void:
	var pp: Vector3 = _player.global_position
	var want := ""
	if _buggy_mounted:
		want = "カーから おりる"
	elif _buggy and pp.distance_to(_buggy_pos) < BUGGY_RANGE:
		want = "カーに のる"
	elif pp.distance_to(_moon_rocket_pos) < ENTER_RANGE:
		want = "おうちへ かえる"
	if want == _moon_btn_text:
		return
	_moon_btn_text = want
	if want == "":
		_btn.visible = false
	else:
		_set_btn(want)


# === 音(もちだんご・月面カー) ===

func _ensure_audio() -> void:
	if _sfx == null:
		_sfx = AudioStreamPlayer.new()
		_sfx.stream = _make_tone(392.0, 587.0, 0.22)
		_sfx.volume_db = -4.0
		add_child(_sfx)
	if _engine == null:
		_engine = AudioStreamPlayer.new()
		_engine.stream = _make_loop_tone(110.0, 0.2, 0.16)
		_engine.volume_db = -10.0
		add_child(_engine)


# 2周波数の やさしい上昇音(sin包絡で角を取る)。
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


# 低くて やわらかい エンジン音(継ぎ目なくループ。freq*dur が整数周期になるよう選ぶ)。
func _make_loop_tone(freq: float, dur: float, vol: float) -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / float(rate)
		var s: float = sin(TAU * freq * t) * vol
		s += sin(TAU * freq * 2.0 * t) * vol * 0.3  # 倍音でエンジンらしさ
		data.encode_s16(i * 2, int(clamp(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	wav.data = data
	return wav


# === メッシュ/コリジョン ヘルパー ===

func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.05
	return m


func _box(size: Vector3, pos: Vector3, color: Color, rough: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(color, rough)
	mi.position = pos
	add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, color: Color, segs: int) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	mi.mesh = c
	mi.material_override = _mat(color, 0.75)
	mi.position = pos
	add_child(mi)


func _cone(radius: float, height: float, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 16
	mi.mesh = c
	mi.material_override = _mat(color, 0.6)
	mi.position = pos
	add_child(mi)


# 光らない(シェーディングする)球。月本体など。
func _sphere(radius: float, pos: Vector3, color: Color, rough: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 48
	s.rings = 24
	mi.mesh = s
	mi.material_override = _mat(color, rough)
	mi.position = pos
	add_child(mi)
	return mi


func _emit_sphere(radius: float, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 20
	s.rings = 12
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.7
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	add_child(mi)


func _local_sphere(root: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	mi.mesh = s
	mi.material_override = _mat(color, 0.6)
	mi.position = pos
	root.add_child(mi)
	return mi


func _local_capsule(root: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	mi.mesh = c
	mi.material_override = _mat(color, 0.6)
	mi.position = pos
	root.add_child(mi)
	return mi


func _local_box(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(color, 0.6)
	mi.position = pos
	root.add_child(mi)
	return mi


func _local_cyl(root: Node3D, radius: float, height: float, pos: Vector3, color: Color, segs: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	mi.mesh = c
	mi.material_override = _mat(color, 0.7)
	mi.position = pos
	root.add_child(mi)
	return mi


# 光る(UNSHADED + emission)球を root の子に。UFO のドーム・あかり、カーのキャノピー等。
func _local_emit(root: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 20
	s.rings = 12
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.7
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	root.add_child(mi)
	return mi


func _add_sphere_collision(radius: float, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	cs.shape = shape
	cs.position = center
	body.add_child(cs)
	add_child(body)


