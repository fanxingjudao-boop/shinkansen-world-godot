extends Node3D

# 飛行機で「そらの おしろ」へ。Main 直下のノード。moon_trip.gd と同じ「別世界ワープ」骨格。
#
# 仕組み:
# - 地上に かわいい飛行機を駐機。近づくと HUD に「そらへ いく」ボタン。
# - 押すと: 飛行機をプレイヤーに装着 → ゆっくり上昇する自動飛行(操作いらず・カメラが追う)
#   → フェードして 遠く高所の「空の城ワールド」へ。雲の島の上に城が建つ。
# - 飛行機は1機だけで、プレイヤーと一緒に移動する(着陸した所に駐機)。空の城でも
#   その飛行機に近づくと「おうちへ かえる」。失敗概念なし・いつでも帰れる。
#
# 怖くない配慮(最重要=空から落ちる恐怖を作らない):
# - 雲の島の上は平らで歩ける + ふちに見えない高い壁 + 落ちても自動で島へ戻す。
# - ふわふわ重力で やさしく跳べる。夜にしない(常に明るい夢のような空)。
# - 飛行は操作不要・酔わないゆるやかな動き・カメラが景色を見せる。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const AIRSTRIP_POS := Vector2(-34.0, 18.0)       # 地上の飛行場(原点・ロケットと離す)
const SKY_POS := Vector3(-2000.0, 400.0, -2000.0) # 空の城(遠く・高所。島の上面が SKY_POS.y)
const SKY_GRAVITY := 0.4                          # 空の城の重力(ふわっと、月ほど低くない)
const ENTER_RANGE := 9.0                          # 飛行機にこの距離でボタンが出る
const FADE_TIME := 0.35
const FLIGHT_TIME := 2.6                          # 自動上昇飛行の時間(見て楽しい長さ)
const ISLAND_R := 24.0                            # 雲の島(あそべる ひろさ)

# 色
const CLOUD_W := Color(0.97, 0.98, 1.0)
const CLOUD_SH := Color(0.85, 0.88, 0.96)
const SKY_BG := Color(0.45, 0.68, 0.95)   # すこし濃いめの空色(白い雲とのコントラスト確保)
const IVORY := Color(0.96, 0.93, 0.84)
const IVORY_DK := Color(0.86, 0.82, 0.72)
const ROOF_BLUE := Color(0.42, 0.6, 0.9)
const GOLD := Color(1.0, 0.85, 0.32)
const STONE := Color(0.74, 0.72, 0.68)
const WINDOW_C := Color(0.55, 0.85, 1.0)
const PLANE_RED := Color(0.95, 0.42, 0.45)
const PLANE_CREAM := Color(0.98, 0.96, 0.9)
const FLAG_PINK := Color(1.0, 0.58, 0.75)
const RAINBOW := [Color(1.0, 0.5, 0.5), Color(1.0, 0.74, 0.42), Color(1.0, 0.93, 0.5), Color(0.62, 0.9, 0.6), Color(0.55, 0.8, 1.0), Color(0.7, 0.62, 0.95)]

var _player: CharacterBody3D
var _rig: Node
var _dn: Node
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _hud: Node
var _ride: Node
var _gs: Node
var _btn: BaseButton
var _petals: GPUParticles3D  # さくらふぶき(地上の演出。空では止める)

var _on_sky: bool = false
var _busy: bool = false
var _sky_built: bool = false
var _plane: Node3D            # 1機の飛行機(着陸地に駐機 / 飛行中はプレイヤーの子)
var _prop: Node3D            # プロペラ(回す)
var _park_pos: Vector3 = Vector3.ZERO   # 飛行機の駐機位置(近接判定)
var _decor: Node3D           # 城の上空を旋回する 新幹線(演出)
var _decor_angle: float = 0.0
var _stars: Array = []       # 空の城の ほし [{node, base_y, phase, taken}]
var _sfx: AudioStreamPlayer  # ほし獲得音
var _engine: AudioStreamPlayer  # 飛行中のプロペラ/風音(ループ)
var _btn_text: String = ""


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
	_btn = root.find_child("AirplaneButton", true, false) as BaseButton
	if _btn:
		_btn.pressed.connect(_on_pressed)
		_btn.visible = false
	_ensure_audio()
	# 空の城は重い(島・城・電車・星)ので初回ワープ時に作る。
	# 飛行機は近接判定に要るので最初から作り、地上に駐機。
	_build_plane()
	_park_plane_at(_ground_airstrip())


func _process(delta: float) -> void:
	# プロペラは常に回す(駐機中はゆっくり、飛行中ははやく)
	if _prop:
		_prop.rotate_z(delta * (16.0 if _busy else 3.0))
	if _player == null or _btn == null or _busy:
		return
	if _on_sky:
		# 安全網: 万一 島から落ちたら 島の上へ戻す(空に消えない)
		if _player.global_position.y < SKY_POS.y - 30.0:
			_player.global_position = _sky_spawn()
			_player.velocity = Vector3.ZERO
		# 城の上空を 新幹線が旋回(演出)
		_update_decor(delta)
		# ほしの 浮遊・回転・獲得
		_update_stars(delta)
		var near_home: bool = _player.global_position.distance_to(_park_pos) < ENTER_RANGE
		_set_btn_state("おうちへ かえる" if near_home else "")
	else:
		var riding: bool = _ride != null and _ride.has_method("is_riding") and _ride.is_riding()
		var near: bool = (not riding) and _player.global_position.distance_to(_park_pos) < ENTER_RANGE
		_set_btn_state("そらへ いく" if near else "")


# ボタンの表示テキスト(変化したときだけ更新してチラつき防止)。
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
	if _on_sky:
		if _player.global_position.distance_to(_park_pos) < ENTER_RANGE:
			_go_home()
		return
	# 乗車中は飛行機に乗らない(状態崩壊の防止)
	if _ride != null and _ride.has_method("is_riding") and _ride.is_riding():
		return
	if _player.global_position.distance_to(_park_pos) < ENTER_RANGE:
		_go_sky()


# === 飛行(自動上昇 → フェード → 別世界) ===

func _go_sky() -> void:
	_busy = true
	_hide_btn()
	if not _sky_built:
		_build_sky()
		_sky_built = true
	_begin_flight()
	var dest: Vector3 = _player.global_position + Vector3(8, 26, -14)  # 上昇 + 前へ
	_climb_then(dest, _arrive_sky_mid, _arrive_sky_done)


func _go_home() -> void:
	_busy = true
	_hide_btn()
	_begin_flight()
	var dest: Vector3 = _player.global_position + Vector3(6, 20, -10)
	_climb_then(dest, _arrive_home_mid, _arrive_home_done)


# 上昇アーク(プレイヤーを動かす=既存カメラが追う)→ フェード中点 midpoint → 完了 done。
func _climb_then(dest: Vector3, midpoint: Callable, done: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(_player, "global_position", dest, FLIGHT_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_plane, "rotation:z", 0.22, FLIGHT_TIME * 0.6) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: _transition(midpoint, done))


# 飛行開始: 飛行機をプレイヤーの子に装着し、通常移動を止める。
func _begin_flight() -> void:
	if _plane.get_parent() != _player:
		if _plane.get_parent():
			_plane.get_parent().remove_child(_plane)
		_player.add_child(_plane)
	_plane.position = Vector3(0, -0.1, 0)
	_plane.rotation = Vector3.ZERO
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	_player.set("gravity_scale", 0.0)
	if _engine:
		_engine.play()


func _end_flight_physics() -> void:
	_player.set_physics_process(true)
	if _engine:
		_engine.stop()


func _arrive_sky_mid() -> void:
	_on_sky = true
	_player.global_position = _sky_spawn()
	_player.velocity = Vector3.ZERO
	_park_plane_at(_sky_airstrip())     # 飛行機を 空の城に駐機(プレイヤーは降りる)
	_player.set("gravity_scale", SKY_GRAVITY)
	_end_flight_physics()
	_snap_cam()
	_apply_sky_env()
	if _gs and _gs.has_method("set_sky_castle_visited"):
		_gs.set_sky_castle_visited()


func _arrive_sky_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("そらの おしろに とうちゃく!")
	_busy = false


func _arrive_home_mid() -> void:
	_on_sky = false
	var gy: float = TerrainHeight.compute_height(AIRSTRIP_POS.x + 4.0, AIRSTRIP_POS.y) + 1.5
	_player.global_position = Vector3(AIRSTRIP_POS.x + 4.0, gy, AIRSTRIP_POS.y)
	_player.velocity = Vector3.ZERO
	_park_plane_at(_ground_airstrip())
	_player.set("gravity_scale", 1.0)
	_end_flight_physics()
	_snap_cam()
	_restore_earth_env()


func _arrive_home_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ただいま!")
	_busy = false


# 飛行機を pos に駐機(self の子に戻して位置を置く)。_park_pos を更新。
func _park_plane_at(pos: Vector3) -> void:
	if _plane.get_parent():
		_plane.get_parent().remove_child(_plane)
	add_child(_plane)
	_plane.global_position = pos
	_plane.rotation = Vector3.ZERO
	_park_pos = pos


func _ground_airstrip() -> Vector3:
	var gy: float = TerrainHeight.compute_height(AIRSTRIP_POS.x, AIRSTRIP_POS.y)
	return Vector3(AIRSTRIP_POS.x, gy + 0.6, AIRSTRIP_POS.y)


func _sky_airstrip() -> Vector3:
	return SKY_POS + Vector3(0, 0.6, 12)


func _sky_spawn() -> Vector3:
	return SKY_POS + Vector3(0, 3, 6)


func _snap_cam() -> void:
	if _rig and _rig.has_method("snap_to_target"):
		_rig.snap_to_target()


# 空の城の空に切り替え(明るい夢空だが、白飛びせず コントラストのある見やすい昼)。
# 以前は ambient 0.95 が強すぎて陰影が消え 真っ白で見えにくかった → ぐっと下げて
# 背景は すこし濃いめの青にして 雲・城・電車が はっきり見えるようにする。
func _apply_sky_env() -> void:
	if _dn:
		_dn.set("paused", true)
	_set_petals(false)  # 空では さくらふぶき を止める
	if _env and _env.environment:
		var e := _env.environment
		e.background_color = SKY_BG          # すこし濃いめの青(下の定数で調整)
		e.ambient_light_color = Color(0.72, 0.79, 0.92)
		e.ambient_light_energy = 0.5         # 0.95→0.5(白飛び解消・陰影で立体感)
		e.fog_light_color = Color(0.72, 0.83, 0.98)
	if _sun:
		_sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
		_sun.light_color = Color(1.0, 0.99, 0.95)
		_sun.light_energy = 1.05


func _restore_earth_env() -> void:
	if _dn:
		_dn.set("paused", false)
		_dn.set("time_of_day", _dn.get("time_of_day"))
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


# === 飛行機(1機。プレイヤーと一緒に移動) ===

func _build_plane() -> void:
	_plane = Node3D.new()
	# 胴体(横に寝かせたカプセル。鼻先 -z)
	var fus := _lcap(_plane, 0.6, 2.6, Vector3(0, 0.55, 0), PLANE_RED)
	fus.rotation.x = PI * 0.5
	# 主翼(横に広い薄い箱)
	_lbox(_plane, Vector3(5.2, 0.16, 1.1), Vector3(0, 0.55, 0.1), PLANE_CREAM)
	# 尾翼(垂直)+ 水平尾翼
	_lbox(_plane, Vector3(0.14, 0.9, 0.7), Vector3(0, 0.95, 1.5), PLANE_RED)
	_lbox(_plane, Vector3(1.8, 0.14, 0.5), Vector3(0, 0.6, 1.55), PLANE_CREAM)
	# キャノピー(水色 光る)
	_lemit(_plane, 0.5, Vector3(0, 1.0, -0.2), WINDOW_C).scale = Vector3(1.0, 0.8, 1.3)
	# プロペラ(鼻先で回る)
	_prop = Node3D.new()
	_prop.position = Vector3(0, 0.55, -1.95)
	_plane.add_child(_prop)
	_lcyl(_prop, 0.16, 0.18, Vector3.ZERO, GOLD, 10)        # ハブ
	_lbox(_prop, Vector3(0.12, 1.5, 0.06), Vector3.ZERO, Color(0.3, 0.3, 0.34))  # 羽根
	_lbox(_prop, Vector3(1.5, 0.12, 0.06), Vector3.ZERO, Color(0.3, 0.3, 0.34))
	# 車輪(小さく2つ)
	for sx in [-1.0, 1.0]:
		var w := _lcyl(_plane, 0.26, 0.2, Vector3(sx * 0.7, 0.1, -0.3), Color(0.3, 0.3, 0.34), 10)
		w.rotation.z = PI * 0.5


# === 空の城ワールド(遠く・高所、初回のみ生成) ===

func _build_sky() -> void:
	# 雲の島(平らな上面 + ふわふわ見た目 + 当たり判定)
	_build_cloud_island(SKY_POS, ISLAND_R)
	# 飛び石の雲(ふわふわ重力で渡れる)
	_build_cloud_island(SKY_POS + Vector3(34, -3, 6), 8.0)
	_build_cloud_island(SKY_POS + Vector3(28, -1, -22), 9.0)
	_build_cloud_island(SKY_POS + Vector3(-30, 2, -10), 8.5)
	# レインボーの橋(島から 飛び石へ)
	_build_rainbow(SKY_POS + Vector3(20, 1, 4), SKY_POS + Vector3(34, 1, 6))
	# お城(島の中央)
	_build_castle(SKY_POS)
	# 城の上空を旋回する 新幹線(演出: 前回「城を電車が走る」の空版)
	_build_decor_train()
	# ほし(城のまわりに。近づくと ほし+1)
	_build_sky_stars()


# 雲の島: 平らな当たり判定(歩ける)+ ふわふわした見た目 + ふちの安全壁。
func _build_cloud_island(center: Vector3, radius: float) -> void:
	# 当たり判定は 平らな円柱(上面が center.y)= 歩きやすく落ちにくい
	_add_cyl_collision(radius, 5.0, center + Vector3(0, -2.5, 0))
	# 見た目: つぶした白い雲(本体 + まわりに ぽこぽこ)
	var body := _lsphere(self, radius, center + Vector3(0, -1.2, 0), CLOUD_W)
	body.scale = Vector3(1.0, 0.42, 1.0)
	var n: int = int(radius * 0.7)
	for i in range(n):
		var a: float = float(i) / float(n) * TAU
		var rr: float = radius * 0.82
		var pf := center + Vector3(cos(a) * rr, -0.4, sin(a) * rr)
		var puff := _lsphere(self, radius * 0.26, pf, CLOUD_W)
		puff.scale = Vector3(1.0, 0.7, 1.0)
	# ふちの 見えない高い壁(落下防止)。大きな島だけに付ける。
	if radius >= ISLAND_R - 0.1:
		var m: int = 18
		for k in range(m):
			var a2: float = float(k) / float(m) * TAU
			var wx: float = center.x + cos(a2) * (radius - 0.4)
			var wz: float = center.z + sin(a2) * (radius - 0.4)
			_add_box_collision(Vector3(radius * 0.36, 16.0, 0.8), Vector3(wx, center.y + 8.0, wz), -a2)


# レインボーの橋(7色の帯を 半円アーチで)。
func _build_rainbow(from: Vector3, to: Vector3) -> void:
	var mid := (from + to) * 0.5
	var span: float = from.distance_to(to)
	var rise: float = span * 0.5 + 2.0
	var segs: int = 14
	for ci in range(RAINBOW.size()):
		var yoff: float = float(ci) * 0.45
		for s in range(segs):
			var t: float = float(s) / float(segs - 1)
			var p := from.lerp(to, t)
			p.y = mid.y + sin(t * PI) * rise + yoff
			_lbox(self, Vector3(0.5, 0.32, span / float(segs) + 0.3), p, RAINBOW[ci])


func _build_castle(center: Vector3) -> void:
	# 天守(中央の高い塔)
	_lbox(self, Vector3(7.0, 8.0, 7.0), center + Vector3(0, 4.0, 0), IVORY)
	_lbox(self, Vector3(7.6, 0.6, 7.6), center + Vector3(0, 8.0, 0), IVORY_DK)  # 段
	_lcone(self, 5.6, 3.2, center + Vector3(0, 9.9, 0), ROOF_BLUE)              # 屋根
	_lsphere(self, 0.5, center + Vector3(0, 11.8, 0), GOLD)                     # しゃちほこ風 金玉
	_castle_windows(center + Vector3(0, 4.5, 0), 3.55)
	# 四隅の塔
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var tp := center + Vector3(sx * 6.0, 0, sz * 6.0)
			_lcyl(self, 1.5, 7.0, tp + Vector3(0, 3.5, 0), IVORY, 14)
			_lcone(self, 2.0, 2.4, tp + Vector3(0, 8.2, 0), ROOF_BLUE)
			_build_flag(tp + Vector3(0, 9.4, 0))
	# 城門(正面 +z)
	_lbox(self, Vector3(3.2, 4.0, 1.0), center + Vector3(0, 2.0, 5.2), IVORY_DK)


# 天守の正面(+z)に 光る窓を3つ。
func _castle_windows(base: Vector3, fz: float) -> void:
	for sx in [-1.0, 0.0, 1.0]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.7, 1.1, 0.12)
		mi.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = WINDOW_C
		m.emission_enabled = true
		m.emission = WINDOW_C
		m.emission_energy_multiplier = 0.8
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.position = base + Vector3(sx * 1.6, 0, fz)
		add_child(mi)


func _build_flag(base: Vector3) -> void:
	_lcyl(self, 0.06, 2.2, base + Vector3(0, 1.1, 0), IVORY_DK, 6)
	var cloth := _lbox(self, Vector3(1.2, 0.7, 0.06), base + Vector3(0.63, 1.7, 0), FLAG_PINK)
	cloth.name = "SkyFlag"


# 城の上空を 旋回する 新幹線(白+青、4両)。位置/向きは _process で。
func _build_decor_train() -> void:
	_decor = Node3D.new()
	_decor.position = SKY_POS + Vector3(34, 16, 0)
	add_child(_decor)
	var white := Color(0.97, 0.98, 1.0)
	var blue := Color(0.2, 0.5, 0.85)
	# 先頭(鼻つき)
	var nose := _lcap(_decor, 0.6, 2.6, Vector3(0, 0, -3.4), white)
	nose.rotation.x = PI * 0.5
	for i in range(3):
		var car := _lbox(_decor, Vector3(1.2, 1.1, 2.2), Vector3(0, 0, float(i) * 2.5 - 1.0), white)
		_lbox(_decor, Vector3(1.22, 0.28, 2.0), Vector3(0, 0.1, float(i) * 2.5 - 1.0), blue)  # 青帯
		car.name = "Car%d" % i


func _update_decor(delta: float) -> void:
	if _decor == null:
		return
	_decor_angle += delta * 0.32
	var r: float = 34.0
	_decor.position = Vector3(SKY_POS.x + cos(_decor_angle) * r, SKY_POS.y + 16.0, SKY_POS.z + sin(_decor_angle) * r)
	_decor.rotation.y = -_decor_angle + PI * 0.5


# === ほし(近づくと ほし+1) ===

func _build_sky_stars() -> void:
	var spots := [Vector3(0, 13, 0), Vector3(10, 4, 8), Vector3(-10, 4, 8), Vector3(34, 2, 6), Vector3(-30, 6, -10), Vector3(8, 4, -12)]
	for i in range(spots.size()):
		var p: Vector3 = SKY_POS + spots[i]
		var node := _make_star()
		node.position = p
		add_child(node)
		_stars.append({"node": node, "base_y": p.y, "phase": float(i) * 1.1, "taken": false})


func _make_star() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.55
	s.height = 1.1
	s.radial_segments = 6
	s.rings = 4
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.88, 0.4)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.88, 0.4)
	m.emission_energy_multiplier = 2.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	return mi


func _update_stars(delta: float) -> void:
	if _stars.is_empty():
		return
	var pp: Vector3 = _player.global_position
	for st in _stars:
		if st["taken"]:
			continue
		var node: Node3D = st["node"]
		node.rotate_y(1.2 * delta)
		st["phase"] += delta * 1.5
		node.position.y = st["base_y"] + sin(st["phase"]) * 0.3
		if node.global_position.distance_to(pp) < 2.8:
			_collect_star(st)


func _collect_star(st: Dictionary) -> void:
	st["taken"] = true
	var node: Node3D = st["node"]
	_spawn_burst(node.global_position, Color(1.0, 0.88, 0.4))
	if _gs and _gs.has_method("add_star"):
		_gs.add_star()
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ほしを ゲット!")
	if _player and _player.has_method("celebrate"):
		_player.celebrate()
	if _sfx:
		_sfx.play()
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 1.8, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ZERO, 0.3)
	tw.parallel().tween_property(node, "position:y", st["base_y"] + 2.5, 0.3)
	tw.tween_callback(node.queue_free)


func _spawn_burst(pos: Vector3, color: Color) -> void:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.8
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -4.0, 0)
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
		_sfx.stream = _make_tone(880.0, 1320.0, 0.18)
		_sfx.volume_db = -4.0
		add_child(_sfx)
	if _engine == null:
		_engine = AudioStreamPlayer.new()
		_engine.stream = _make_loop_tone(150.0, 0.2, 0.14)
		_engine.volume_db = -11.0
		add_child(_engine)


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


func _make_loop_tone(freq: float, dur: float, vol: float) -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / float(rate)
		var s: float = sin(TAU * freq * t) * vol
		s += sin(TAU * freq * 2.0 * t) * vol * 0.25
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


# === メッシュ/コリジョン ヘルパー(parent を渡して self でもグループでも使える) ===

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
	c.radial_segments = 16
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
	s.radial_segments = 24
	s.rings = 12
	mi.mesh = s
	mi.material_override = _mat(color, 0.85)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _lcap(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	mi.mesh = c
	mi.material_override = _mat(color, 0.6)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _lemit(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 18
	s.rings = 10
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


func _add_cyl_collision(radius: float, height: float, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position = center
	body.add_child(cs)
	add_child(body)
