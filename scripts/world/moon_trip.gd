extends Node3D

# 月(つき)への旅行。Main 直下のノード。
#
# 仕組み:
# - 地球(いつもの世界)に「ロケットの発射台」を建てる。プレイヤーが近づくと
#   HUD に「つきへ いく」ボタンが出る。押すとフェードして月へワープ。
# - 月は遠く(MOON_POS)に作った灰色の台。背景を宇宙の黒にし、大きな地球と星、
#   つきのうさぎを置く。重力を弱く(ふわっと跳べる)する。
# - 月では「おうちへ かえる」ボタンで地球に戻れる。失敗概念なし・いつでも帰れる。
#
# 怖くない配慮: 真っ暗にしすぎない(環境光は残す)、急に動かない(フェード)、
# 台から落ちても自動で台の上へ戻す + ふちに見えない壁。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const LAUNCH_POS := Vector2(26.0, 22.0)        # 地球の発射台(プレイヤー初期 (0,0,0) の近く)
const MOON_POS := Vector3(2000.0, 60.0, 2000.0) # 月(遠くの宇宙)
const MOON_RADIUS := 40.0
const ENTER_RANGE := 8.5                        # ロケットにこの距離で「つきへ いく」が出る
const MOON_GRAVITY := 0.16                      # 月の重力倍率(ふわっと)
const FADE_TIME := 0.35

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

var _on_moon: bool = false
var _busy: bool = false
var _rocket_pos: Vector3 = Vector3.ZERO
var _moon_built: bool = false   # 月は初回ワープ時に組み立てる(起動時のノード/メモリ節約)


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
		# 安全網: 万一ふちの外へ出て落ちたら、台の上へ戻す(宇宙に消えない)
		if _player.global_position.y < MOON_POS.y - 25.0:
			_player.global_position = MOON_POS + Vector3(0, 3, 0)
			_player.velocity = Vector3.ZERO
		if not _btn.visible:
			_set_btn("おうちへ かえる")
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
		_player.global_position = MOON_POS + Vector3(0, 4, 0)
		_player.velocity = Vector3.ZERO
		_player.set("gravity_scale", MOON_GRAVITY)
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
	_btn.visible = false
	var gy: float = TerrainHeight.compute_height(LAUNCH_POS.x + 4.0, LAUNCH_POS.y) + 1.5
	var home := Vector3(LAUNCH_POS.x + 4.0, gy, LAUNCH_POS.y)
	_transition(func() -> void:
		_on_moon = false
		_player.global_position = home
		_player.velocity = Vector3.ZERO
		_player.set("gravity_scale", 1.0)
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
	var base := Vector3(LAUNCH_POS.x, gy, LAUNCH_POS.y)
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
	_rocket_pos = Vector3(base.x, body_y + 2.0, base.z)


# === 月(遠くの宇宙) ===

func _build_moon() -> void:
	# 月の台(灰色の厚い円盤)+ 当たり判定。上面が MOON_POS.y。
	_cyl(MOON_RADIUS, 2.4, MOON_POS + Vector3(0, -1.2, 0), MOON_GRAY, 28)
	_add_cylinder_collision(MOON_RADIUS, 2.4, MOON_POS + Vector3(0, -1.2, 0))
	# クレーター(へこんだ濃い灰の薄い円)
	var spots := [Vector2(12, 8), Vector2(-16, -6), Vector2(6, -18), Vector2(-10, 16), Vector2(22, -4), Vector2(-22, 6)]
	for s in spots:
		_cyl(4.0 + absf(s.x) * 0.1, 0.3, MOON_POS + Vector3(s.x, 0.05, s.y), MOON_GRAY_DK, 12)
	# ふちの壁(落ちない・見えない当たり判定 + 低い見える縁)
	_build_moon_rim()
	# 大きな地球(空に浮かぶ、光る青と緑)
	_build_earth_in_sky()
	# 星(まわりにキラキラ)
	_build_stars()
	# つきのうさぎ(白くてかわいい)を2匹
	_build_moon_bunny(MOON_POS + Vector3(7, 0.0, -3), 0.0)
	_build_moon_bunny(MOON_POS + Vector3(-6, 0.0, 5), 1.2)
	# 旗(桜色)
	_box(Vector3(0.08, 4.0, 0.08), MOON_POS + Vector3(14, 2.0, 10), MOON_GRAY_DK, 0.6)
	var cloth := _box(Vector3(1.6, 0.9, 0.06), MOON_POS + Vector3(14.85, 3.4, 10), Color(1.0, 0.58, 0.75), 0.6)
	cloth.name = "MoonFlag"


# ふちの壁(16 分割の見えない当たり判定 + 低い見える縁)で台から落ちない。
func _build_moon_rim() -> void:
	var n: int = 18
	for i in range(n):
		var a: float = float(i) / float(n) * TAU
		var rx: float = MOON_POS.x + cos(a) * (MOON_RADIUS - 0.6)
		var rz: float = MOON_POS.z + sin(a) * (MOON_RADIUS - 0.6)
		# 低い見える縁
		var seg := _box(Vector3(MOON_RADIUS * 0.36, 0.8, 0.6), Vector3(rx, MOON_POS.y + 0.4, rz), MOON_GRAY_DK, 0.7)
		seg.rotation.y = -a
		# 高い見えない当たり判定(落下防止)。月は低重力でジャンプ到達が高い(~13m)ので
		# 飛び越えられないよう十分高く(18m)する。
		_add_box_collision(Vector3(MOON_RADIUS * 0.36, 18.0, 0.8), Vector3(rx, MOON_POS.y + 9.0, rz), -a)


func _build_earth_in_sky() -> void:
	var pos := MOON_POS + Vector3(-70, 120, -220)
	_emit_sphere(42.0, pos, EARTH_BLUE)
	# 大陸(緑)を数個ぺたぺた
	var conts := [Vector3(10, 14, -38), Vector3(-18, -6, -38), Vector3(20, -16, -34), Vector3(-8, 22, -34)]
	for c in conts:
		_emit_sphere(8.0, pos + c, EARTH_GREEN)


func _build_stars() -> void:
	# 月のまわりのドーム状に小さな光る点を散らす(seed 固定で毎回同じ)
	seed(7777)
	for i in range(40):
		var a: float = randf() * TAU
		var el: float = randf_range(0.1, 1.2)
		var r: float = randf_range(120.0, 260.0)
		var p := MOON_POS + Vector3(cos(a) * r, 40.0 + sin(el) * r * 0.8, sin(a) * r)
		_emit_sphere(randf_range(0.8, 1.8), p, Color(1, 1, 0.95))


# 白くてまるい「つきのうさぎ」(体 + 長い耳 + 目)。静止。
func _build_moon_bunny(pos: Vector3, face_yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = face_yaw
	add_child(root)
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


func _add_cylinder_collision(radius: float, height: float, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position = center
	body.add_child(cs)
	add_child(body)


func _add_box_collision(size: Vector3, center: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = Vector3.ZERO
	body.position = center
	body.add_child(cs)
	add_child(body)
