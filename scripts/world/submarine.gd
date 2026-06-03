extends Node3D

# 潜水艦で「うみの そこ」を 自動運転で探索。Main 直下のノード。
# moon_trip / sky_castle と同じ「乗り物→別世界ワープ + 乗り物を装着して自動移動」骨格。
#
# 仕組み:
# - 湖(TerrainHeight.LAKE_POS)に 半透明の水面 + かわいい黄色い潜水艦を駐艇。
#   近づくと HUD `SubButton`「うみに もぐる」。
# - 押すと フェード → 遠く深所の「海の世界」へ。プレイヤーを潜水艦に装着し
#   `set_physics_process(false)`+gravity0。潜水艦が サンゴの庭のまわりを
#   **ゆるやかに連続自動巡航**(操作いらず)。たくさんの魚を眺める。
# - 海にいる間は「うみから あがる」を常時表示。いつでも浮上できる。
#
# 怖くない配慮(厳守): 明るい青の水中(暗くしない)・サメや不気味生物なし・
# 急に出てこない・自動運転で安心・失敗/落下なし・いつでも浮上。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const SUB_DOCK := Vector2(-78.0, 130.0)            # 湖の中(発着)。湖中心(-88,140)から少し岸より
const SEA_POS := Vector3(-2000.0, -600.0, 2000.0)  # 海の世界(遠く・深所)。砂の床が SEA_POS.y
const ENTER_RANGE := 10.0
const FADE_TIME := 0.35
const CRUISE_SPEED := 3.6           # 自動巡航の速さ(ゆっくり=酔わない)
const CRUISE_Y := 9.0               # 床から上の 巡航する高さ
const CRUISE_R := 24.0              # 巡航ループの半径(サンゴの庭を囲む)
const PEARL_GET_RANGE := 3.2

const WATER_C := Color(0.34, 0.64, 0.82, 0.55)
const SEA_BG := Color(0.20, 0.55, 0.70)
const SAND := Color(0.93, 0.87, 0.64)
const SAND_DK := Color(0.82, 0.74, 0.52)
const SUB_BODY := Color(1.0, 0.85, 0.35)   # 黄色い潜水艦
const SUB_TRIM := Color(0.95, 0.45, 0.45)
const DOME_C := Color(0.6, 0.85, 1.0)
const SEAWEED_C := Color(0.4, 0.75, 0.5)
const CORAL_COLS := [Color(1.0, 0.6, 0.72), Color(1.0, 0.74, 0.42), Color(0.7, 0.62, 0.95), Color(0.5, 0.82, 0.78), Color(1.0, 0.85, 0.5)]
const FISH_COLS := [Color(1.0, 0.6, 0.4), Color(1.0, 0.82, 0.4), Color(0.55, 0.8, 1.0), Color(1.0, 0.6, 0.78), Color(0.6, 0.85, 0.6), Color(0.85, 0.65, 1.0)]

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

var _on_sea: bool = false
var _busy: bool = false
var _sea_built: bool = false
var _sub: Node3D
var _prop: Node3D
var _sub_pos: Vector3 = Vector3.ZERO   # 湖の駐艇位置(近接判定)
var _cruise: Array = []                # 巡航 waypoint(Vector3)
var _cruise_i: int = 0
var _fish: Array = []                   # [{node, tail, cx, cy, cz, r, spd, ang, amp}]
var _pearls: Array = []                 # [{node, base_y, phase, taken}]
var _sonar: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _btn_text: String = ""
var _bubble_timer: float = 0.0
# 帰還時に戻す 地球の fog 設定(海で変えるので 退避しておく)
var _earth_fog_density: float = 0.0009
var _earth_fog_enabled: bool = true


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
	_btn = root.find_child("SubButton", true, false) as BaseButton
	if _btn:
		_btn.pressed.connect(_on_pressed)
		_btn.visible = false
	if _env and _env.environment:
		_earth_fog_density = _env.environment.fog_density
		_earth_fog_enabled = _env.environment.fog_enabled
	_ensure_audio()
	# 海の世界は重いので初回潜航時に作る。湖の水面と潜水艦は最初から。
	_build_lake_water()
	_build_submarine()
	_park_sub_at(_dock_pos())


func _process(delta: float) -> void:
	if _prop:
		_prop.rotate_z(delta * (10.0 if _on_sea else 2.0))
	if _player == null or _btn == null or _busy:
		return
	if _on_sea:
		_drive_cruise(delta)
		_update_fish(delta)
		_update_pearls(delta)
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			_bubble_timer = 0.5
			if _sub:
				_spawn_bubbles(_sub.global_position + Vector3(0, 0.6, 1.8))
		_set_btn_state("うみから あがる")
	else:
		var riding: bool = _ride != null and _ride.has_method("is_riding") and _ride.is_riding()
		var near: bool = (not riding) and _player.global_position.distance_to(_sub_pos) < ENTER_RANGE
		_set_btn_state("うみに もぐる" if near else "")


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
	if _on_sea:
		_surface()
		return
	if _ride != null and _ride.has_method("is_riding") and _ride.is_riding():
		return
	if _player.global_position.distance_to(_sub_pos) < ENTER_RANGE:
		_dive()


# === 潜航 / 浮上 ===

# おでかけメニューから 直接ワープ(潜水艦の近くにいなくても)。
func warp_in() -> void:
	if _busy or _on_sea:
		return
	_dive()


func is_active() -> bool:
	return _on_sea


func _dive() -> void:
	_busy = true
	_hide_btn()
	if not _sea_built:
		_build_sea()
		_sea_built = true
	_transition(_arrive_sea_mid, _arrive_sea_done)


func _surface() -> void:
	_busy = true
	_hide_btn()
	_transition(_arrive_home_mid, _arrive_home_done)


func _arrive_sea_mid() -> void:
	_on_sea = true
	_begin_ride()
	_cruise_i = 0
	if not _cruise.is_empty():
		_player.global_position = _cruise[0]
	_player.velocity = Vector3.ZERO
	_snap_cam()
	_apply_sea_env()
	if _gs and _gs.has_method("set_submarine_visited"):
		_gs.set_submarine_visited()


func _arrive_sea_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("うみの なかへ!")
	_busy = false


func _arrive_home_mid() -> void:
	_on_sea = false
	_end_ride()
	var p := _dock_stand_pos()
	_player.global_position = p
	_player.velocity = Vector3.ZERO
	_snap_cam()
	_restore_earth_env()


func _arrive_home_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ぷはー!")
	_busy = false


# 潜水艦をプレイヤーに装着し、通常移動を止める(自動巡航のため)。
func _begin_ride() -> void:
	if _sub.get_parent() != _player:
		if _sub.get_parent():
			_sub.get_parent().remove_child(_sub)
		_player.add_child(_sub)
	_sub.position = Vector3(0, 0.1, 0)
	_sub.rotation = Vector3.ZERO
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	_player.set("gravity_scale", 0.0)
	if _sonar:
		_sonar.play()


func _end_ride() -> void:
	_park_sub_at(_dock_pos())
	_player.set_physics_process(true)
	_player.set("gravity_scale", 1.0)
	if _sonar:
		_sonar.stop()


func _park_sub_at(pos: Vector3) -> void:
	if _sub.get_parent():
		_sub.get_parent().remove_child(_sub)
	add_child(_sub)
	_sub.global_position = pos
	_sub.rotation = Vector3.ZERO
	_sub_pos = pos


# 自動巡航: いまの waypoint へ一定速度で進み、着いたら次へ(ループ)。潜水艦は進行方向へ。
func _drive_cruise(delta: float) -> void:
	if _cruise.is_empty():
		return
	var target: Vector3 = _cruise[_cruise_i]
	var to: Vector3 = target - _player.global_position
	var d: float = to.length()
	if d < 1.2:
		_cruise_i = (_cruise_i + 1) % _cruise.size()
		return
	var dir: Vector3 = to / d
	_player.global_position += dir * min(CRUISE_SPEED * delta, d)
	# 潜水艦の鼻(-z)を進行方向(水平成分)へ なめらかに向ける。プレイヤー本体は回さない
	# (カメラを一貫させる)。_sub はプレイヤーの子で 本体は無回転なので local=world。
	var flat := Vector2(dir.x, dir.z)
	if _sub and flat.length() > 0.05:
		var target_yaw: float = atan2(-dir.x, -dir.z)
		_sub.rotation.y = lerp_angle(_sub.rotation.y, target_yaw, clamp(4.0 * delta, 0.0, 1.0))


func _snap_cam() -> void:
	if _rig and _rig.has_method("snap_to_target"):
		_rig.snap_to_target()


# === 環境(水中 / 地球) ===

func _apply_sea_env() -> void:
	if _dn:
		_dn.set("paused", true)
	_set_petals(false)
	if _env and _env.environment:
		var e := _env.environment
		e.background_color = SEA_BG
		e.ambient_light_color = Color(0.6, 0.78, 0.86)
		e.ambient_light_energy = 0.7          # 明るい水中(暗くしない=怖くない)
		e.fog_enabled = true
		e.fog_density = 0.013                 # 水中の遠近フェード(でも近くは よく見える)
		e.fog_light_color = Color(0.35, 0.66, 0.78)
	if _sun:
		_sun.rotation_degrees = Vector3(-72.0, -18.0, 0.0)  # 上から
		_sun.light_color = Color(0.8, 0.92, 1.0)
		_sun.light_energy = 0.85


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


# === 湖の水面 + 潜水艦 ===

func _dock_pos() -> Vector3:
	return Vector3(SUB_DOCK.x, TerrainHeight.compute_water_y(), SUB_DOCK.y)


func _dock_stand_pos() -> Vector3:
	# 浮上後に プレイヤーが立つ場所(湖の岸ぎわ・地面の上)
	var gy: float = TerrainHeight.compute_height(SUB_DOCK.x + 3.0, SUB_DOCK.y)
	return Vector3(SUB_DOCK.x + 3.0, gy + 1.0, SUB_DOCK.y)


# 湖の上に 半透明の水色ディスク(当たり判定なし=歩いて潜水艦に近づける)。
func _build_lake_water() -> void:
	var lp := TerrainHeight.LAKE_POS
	var wy: float = TerrainHeight.compute_water_y()
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = TerrainHeight.LAKE_RADIUS
	c.bottom_radius = TerrainHeight.LAKE_RADIUS
	c.height = 0.1
	c.radial_segments = 32
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = WATER_C
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.2
	m.roughness = 0.15
	mi.material_override = m
	mi.position = Vector3(lp.x, wy, lp.y)
	add_child(mi)


func _build_submarine() -> void:
	_sub = Node3D.new()
	# 胴体(横に寝かせた黄色いカプセル。鼻先 -z)
	var fus := _lcap(_sub, 0.9, 4.0, Vector3(0, 0, 0), SUB_BODY)
	fus.rotation.x = PI * 0.5
	# 赤い帯
	var band := _lcyl(_sub, 0.92, 0.5, Vector3(0, 0, 0.6), SUB_TRIM, 18)
	band.rotation.x = PI * 0.5
	# ドーム窓(前のほう・光る水色)
	_lemit(_sub, 0.7, Vector3(0, 0.45, -1.4), DOME_C).scale = Vector3(1.1, 0.9, 1.0)
	# 司令塔
	_lcyl(_sub, 0.45, 0.8, Vector3(0, 0.95, 0.2), SUB_BODY, 14)
	# ペリスコープ
	_lcyl(_sub, 0.07, 0.9, Vector3(0, 1.6, 0.2), SUB_TRIM, 8)
	_lbox(_sub, Vector3(0.3, 0.12, 0.12), Vector3(0.12, 2.0, 0.2), SUB_TRIM)
	# 横の まる窓(光る)
	for sz in [-0.6, 0.4, 1.2]:
		_lemit(_sub, 0.18, Vector3(0.9, 0.1, sz), DOME_C)
		_lemit(_sub, 0.18, Vector3(-0.9, 0.1, sz), DOME_C)
	# 横ひれ
	for sx in [-1.0, 1.0]:
		_lbox(_sub, Vector3(1.0, 0.12, 0.7), Vector3(sx * 1.2, -0.2, 1.0), SUB_TRIM)
	# 尾の 垂直ひれ
	_lbox(_sub, Vector3(0.14, 0.9, 0.6), Vector3(0, 0.55, 1.9), SUB_TRIM)
	# プロペラ(後ろ +z で回る)
	_prop = Node3D.new()
	_prop.position = Vector3(0, 0, 2.2)
	_sub.add_child(_prop)
	_lcyl(_prop, 0.14, 0.16, Vector3.ZERO, Color(0.5, 0.5, 0.55), 8)
	_lbox(_prop, Vector3(0.1, 1.0, 0.05), Vector3.ZERO, Color(0.6, 0.6, 0.65))
	_lbox(_prop, Vector3(1.0, 0.1, 0.05), Vector3.ZERO, Color(0.6, 0.6, 0.65))


# === 海の世界(遠く・深所、初回のみ生成) ===

func _build_sea() -> void:
	var c := SEA_POS
	# 砂の床(大きな円盤)+ ゆるい砂山
	var floor_mi := _lcyl(self, 90.0, 2.0, c + Vector3(0, -1.0, 0), SAND, 36)
	floor_mi.name = "SeaFloor"
	for i in range(10):
		var a: float = float(i) / 10.0 * TAU
		var rr: float = 30.0 + float(i % 3) * 12.0
		var mound := _lsphere(self, 6.0 + float(i % 4) * 2.0, c + Vector3(cos(a) * rr, -1.0, sin(a) * rr), SAND_DK)
		mound.scale = Vector3(1.0, 0.3, 1.0)
	# サンゴの庭(中央)・岩・海藻・宝箱
	_build_coral_garden(c)
	_build_seaweed_patch(c)
	_build_rocks(c)
	_build_treasure(c + Vector3(6, 0.6, -4))
	# 海底からの 泡の噴出(2か所・ずっと出る)
	_build_bubble_vent(c + Vector3(-10, 0, 8))
	_build_bubble_vent(c + Vector3(14, 0, -6))
	# 魚の群れ(たくさん)
	_build_fish()
	# 大きな やさしい生き物(くじら・かめ)
	_build_whale(c)
	_build_turtle(c)
	# しんじゅ(ごほうび)
	_build_pearls(c)
	# 巡航ルート(サンゴの庭を囲む ゆるい大ループ + 上下)
	_cruise.clear()
	var n: int = 12
	for i in range(n):
		var a: float = float(i) / float(n) * TAU
		var y: float = c.y + CRUISE_Y + sin(a * 2.0) * 2.5
		_cruise.append(c + Vector3(cos(a) * CRUISE_R, y - c.y, sin(a) * CRUISE_R))


func _build_coral_garden(c: Vector3) -> void:
	for i in range(14):
		var a: float = float(i) / 14.0 * TAU + 0.3
		var rr: float = 4.0 + float(i % 4) * 3.0
		var base := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		var col: Color = CORAL_COLS[i % CORAL_COLS.size()]
		var kind: int = i % 3
		if kind == 0:
			# 枝サンゴ(細い円柱を 数本ひろげる)
			for k in range(4):
				var ba: float = float(k) / 4.0 * TAU
				var br := _lcyl(self, 0.18, 2.2 + float(k % 2), base + Vector3(cos(ba) * 0.5, 1.1, sin(ba) * 0.5), col, 8)
				br.rotation.z = cos(ba) * 0.4
				br.rotation.x = sin(ba) * 0.4
		elif kind == 1:
			# 扇サンゴ(平たい三角)
			var fan := _lcone(self, 1.6, 2.6, base + Vector3(0, 1.3, 0), col)
			fan.scale = Vector3(1.0, 1.0, 0.25)
		else:
			# 丸サンゴ(ぷくぷく)
			for k in range(3):
				_lsphere(self, 0.7 - float(k) * 0.15, base + Vector3(float(k) * 0.4 - 0.4, 0.6 + float(k) * 0.4, 0), col)


func _build_seaweed_patch(c: Vector3) -> void:
	for i in range(18):
		var a: float = float(i) / 18.0 * TAU * 1.7
		var rr: float = 8.0 + float(i % 5) * 4.0
		var base := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		var h: float = 2.5 + float(i % 4)
		var stalk := _lbox(self, Vector3(0.25, h, 0.25), base + Vector3(0, h * 0.5, 0), SEAWEED_C)
		# ゆらゆら(左右に ゆっくり)
		stalk.rotation.z = -0.18
		var tw := create_tween().set_loops()
		tw.tween_property(stalk, "rotation:z", 0.18, 1.6 + float(i % 3) * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(stalk, "rotation:z", -0.18, 1.6 + float(i % 3) * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _build_rocks(c: Vector3) -> void:
	for i in range(8):
		var a: float = float(i) / 8.0 * TAU + 0.7
		var rr: float = 16.0 + float(i % 3) * 8.0
		var rock := _lsphere(self, 1.6 + float(i % 3) * 0.8, c + Vector3(cos(a) * rr, 0.3, sin(a) * rr), Color(0.55, 0.58, 0.6))
		rock.scale = Vector3(1.0, 0.7, 1.1)


func _build_treasure(pos: Vector3) -> void:
	_lbox(self, Vector3(1.6, 1.0, 1.1), pos, Color(0.6, 0.42, 0.26))      # 箱
	_lbox(self, Vector3(1.7, 0.3, 1.2), pos + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.35))  # 金のふち
	# 中の キラキラ(光る玉)
	for k in range(3):
		_lemit(self, 0.22, pos + Vector3(float(k) * 0.4 - 0.4, 0.7, 0), Color(1.0, 0.9, 0.5))


# === 魚(たくさん) ===

func _build_fish() -> void:
	# 6 つの群れ(色・位置・大きさ違い)。各群れ 8 匹 = 48 匹。
	var centers := [
		Vector3(-8, 8, 4), Vector3(10, 6, 8), Vector3(4, 11, -10),
		Vector3(-12, 5, -8), Vector3(14, 9, 2), Vector3(0, 7, 12),
	]
	for s in range(centers.size()):
		var cc: Vector3 = SEA_POS + centers[s]
		var col: Color = FISH_COLS[s % FISH_COLS.size()]
		var rr: float = 4.0 + float(s % 3) * 1.5
		var spd: float = (0.5 + float(s % 3) * 0.18) * (1.0 if s % 2 == 0 else -1.0)
		for k in range(8):
			var ph: float = float(k) / 8.0 * TAU
			var fish := _make_fish(col, 0.45 + float(k % 3) * 0.12)
			add_child(fish["node"])
			_fish.append({
				"node": fish["node"], "tail": fish["tail"],
				"cx": cc.x, "cy": cc.y + sin(ph) * 1.2, "cz": cc.z,
				"r": rr + float(k % 2) * 0.6, "spd": spd, "ang": ph, "amp": 0.8,
			})


# 魚: 体(つぶした球)+ 尾(コーン)+ 目。鼻先 -z。{node, tail} を返す。
func _make_fish(color: Color, size: float) -> Dictionary:
	var root := Node3D.new()
	var body := _lsphere(root, size, Vector3.ZERO, color)
	body.scale = Vector3(0.7, 0.9, 1.5)   # 前後に長い
	var tail := Node3D.new()
	tail.position = Vector3(0, 0, size * 1.3)
	root.add_child(tail)
	var fin := _lcone(tail, size * 0.6, size * 0.9, Vector3(0, 0, size * 0.3), color)
	fin.rotation.x = -PI * 0.5
	fin.scale = Vector3(1.0, 1.0, 0.3)
	# 目(両側・黒)
	for sx in [-1.0, 1.0]:
		_lemit(root, size * 0.12, Vector3(sx * size * 0.45, size * 0.2, -size * 0.9), Color(0.1, 0.1, 0.12))
	return {"node": root, "tail": tail}


func _update_fish(delta: float) -> void:
	for f in _fish:
		f["ang"] += f["spd"] * delta
		var ang: float = f["ang"]
		var x: float = f["cx"] + cos(ang) * f["r"]
		var z: float = f["cz"] + sin(ang) * f["r"]
		var y: float = f["cy"] + sin(ang * 1.7) * f["amp"]
		var node: Node3D = f["node"]
		node.global_position = Vector3(x, y, z)
		# 進行方向(接線)へ向ける
		var tang := Vector3(-sin(ang), 0.0, cos(ang)) * signf(f["spd"])
		if tang.length() > 0.01:
			node.look_at(node.global_position + tang, Vector3.UP)
		# 尾の ゆれ
		var tail: Node3D = f["tail"]
		tail.rotation.y = sin(ang * 9.0) * 0.5


# === 大きな やさしい生き物 ===

func _build_whale(c: Vector3) -> void:
	var whale := Node3D.new()
	add_child(whale)
	var blue := Color(0.55, 0.72, 0.9)
	var body := _lcap(whale, 2.2, 8.0, Vector3.ZERO, blue)
	body.rotation.x = PI * 0.5
	_lsphere(whale, 1.4, Vector3(0, 0.6, -3.6), Color(0.95, 0.95, 0.98))  # おなか白
	_lcone(whale, 1.8, 2.2, Vector3(0, 0, 4.2), blue).rotation.x = PI * 0.5  # 尾
	for sx in [-1.0, 1.0]:
		_lemit(whale, 0.28, Vector3(sx * 0.9, 0.6, -3.0), Color(0.1, 0.1, 0.12))  # 目
	whale.position = c + Vector3(0, 16, -34)
	# ゆっくり大きく旋回(高いところを 横切る)
	var tw := create_tween().set_loops()
	tw.tween_property(whale, "position", c + Vector3(0, 16, 34), 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(whale, "position", c + Vector3(0, 16, -34), 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _build_turtle(c: Vector3) -> void:
	var turtle := Node3D.new()
	add_child(turtle)
	var green := Color(0.45, 0.7, 0.5)
	var shell := _lsphere(turtle, 1.4, Vector3.ZERO, Color(0.5, 0.6, 0.4))
	shell.scale = Vector3(1.2, 0.6, 1.4)
	_lsphere(turtle, 0.5, Vector3(0, 0.1, -1.5), green)   # 頭
	for p in [Vector3(1.1, -0.1, 0.8), Vector3(-1.1, -0.1, 0.8), Vector3(1.1, -0.1, -0.8), Vector3(-1.1, -0.1, -0.8)]:
		var fin := _lcap(turtle, 0.18, 1.0, p, green)
		fin.rotation.z = PI * 0.5
	turtle.position = c + Vector3(20, 6, 0)
	turtle.rotation.y = PI * 0.5
	var tw := create_tween().set_loops()
	tw.tween_property(turtle, "position", c + Vector3(-20, 7, 12), 16.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(turtle, "position", c + Vector3(20, 6, 0), 16.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# === しんじゅ(ごほうび) ===

func _build_pearls(c: Vector3) -> void:
	# 巡航ループの近くに 光る玉を 5 個
	var spots := [0.0, 1.2, 2.6, 3.9, 5.1]
	for i in range(spots.size()):
		var a: float = spots[i]
		var p := c + Vector3(cos(a) * CRUISE_R, CRUISE_Y + sin(a * 2.0) * 2.5 + 1.0, sin(a) * CRUISE_R)
		var mi := _lemit(self, 0.45, p, Color(1.0, 0.95, 0.8))
		_pearls.append({"node": mi, "base_y": p.y, "phase": float(i) * 1.1, "taken": false})


func _update_pearls(delta: float) -> void:
	if _pearls.is_empty():
		return
	var pp: Vector3 = _player.global_position
	for pe in _pearls:
		if pe["taken"]:
			continue
		var node: Node3D = pe["node"]
		node.rotate_y(1.0 * delta)
		pe["phase"] += delta * 1.4
		node.position.y = pe["base_y"] + sin(pe["phase"]) * 0.25
		if node.global_position.distance_to(pp) < PEARL_GET_RANGE:
			_collect_pearl(pe)


func _collect_pearl(pe: Dictionary) -> void:
	pe["taken"] = true
	var node: Node3D = pe["node"]
	_spawn_burst(node.global_position, Color(1.0, 0.95, 0.8))
	if _gs and _gs.has_method("add_star"):
		_gs.add_star()
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("しんじゅ ゲット!")
	if _player and _player.has_method("celebrate"):
		_player.celebrate()
	if _sfx:
		_sfx.play()
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 1.7, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ZERO, 0.28)
	tw.tween_callback(node.queue_free)


# === 泡 ===

func _build_bubble_vent(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 3.0
	p.preprocess = 2.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, 0.8, 0)   # 泡は上へ
	pm.scale_min = 0.12
	pm.scale_max = 0.3
	p.process_material = pm
	p.draw_pass_1 = _bubble_mesh()
	add_child(p)
	p.global_position = pos
	p.emitting = true


func _spawn_bubbles(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 2.0
	p.one_shot = true
	p.explosiveness = 0.5
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.08
	pm.scale_max = 0.2
	p.process_material = pm
	p.draw_pass_1 = _bubble_mesh()
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


func _bubble_mesh() -> QuadMesh:
	var qm := QuadMesh.new()
	qm.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.92, 1.0, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.95, 1.0)
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	return qm


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
	pm.gravity = Vector3(0, 0.4, 0)
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
		_sfx.stream = _make_tone(784.0, 1175.0, 0.2)
		_sfx.volume_db = -4.0
		add_child(_sfx)
	if _sonar == null:
		_sonar = AudioStreamPlayer.new()
		_sonar.stream = _make_loop_tone(220.0, 0.5, 0.10)  # やわらかい低い ハム
		_sonar.volume_db = -14.0
		add_child(_sonar)


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


# === メッシュ ヘルパー(parent を渡して self でもグループでも使える) ===

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
