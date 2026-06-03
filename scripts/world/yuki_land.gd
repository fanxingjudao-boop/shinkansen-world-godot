extends Node3D

# そりで「ゆきの くに」を 自動運転で めぐる。Main 直下のノード。
# submarine / dino_land と同じ「乗り物→別世界ワープ + 乗り物を装着して自動巡航」骨格。
#
# 仕組み:
# - 草原に かわいい そりを駐車。近づくと HUD `YukiButton`「ゆきの くにへ いこう」。
# - 押すと フェード → 遠くの「ゆきの くに」へ。プレイヤーをそりに装着し
#   `set_physics_process(false)`+gravity0。雪景色の間を ゆっくり自動巡航(しゅーっ)。
# - ゆきの クリスタルに近づくと ゲット(ほし)。
# - くにに いる間は「おうちへ かえる」を常時表示。いつでも帰れる。
#
# 怖くない配慮(厳守): 明るい雪あかり(暗い吹雪にしない)・オーロラは やさしく光る・
# しろい動物/ペンギン/ゆきだるまは かわいい・急に出てこない・自動運転で安心・失敗/落下なし。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const SLED_DOCK := Vector2(-56.0, 8.0)              # 地上の駐車(草原・他の乗り物と離す)
const YUKI_POS := Vector3(0.0, 60.0, -2600.0)       # ゆきの くに(遠く・雪原が YUKI_POS.y)
const ENTER_RANGE := 10.0
const FADE_TIME := 0.35
const CRUISE_SPEED := 3.6
const CRUISE_Y := 1.6
const CRUISE_R := 28.0
const GET_RANGE := 4.0

const YUKI_SKY := Color(0.5, 0.6, 0.78)             # 夕暮れ寄りの明るい空(オーロラが映える)
const SNOW := Color(0.96, 0.97, 1.0)
const SNOW_DK := Color(0.84, 0.88, 0.96)
const ICE := Color(0.7, 0.86, 0.95)
const PINE := Color(0.32, 0.5, 0.42)
const TRUNK := Color(0.5, 0.36, 0.24)
const SLED_RED := Color(0.92, 0.42, 0.46)
const SLED_TRIM := Color(0.98, 0.96, 0.9)
const SPRING_C := Color(0.6, 0.85, 0.85, 0.6)       # あったか温泉(半透明)
const AURORA_COLS := [Color(0.4, 0.95, 0.7), Color(0.6, 0.7, 1.0), Color(1.0, 0.7, 0.9)]
const CRYSTAL_C := Color(0.7, 0.92, 1.0)

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

var _on_yuki: bool = false
var _busy: bool = false
var _world_built: bool = false
var _sled: Node3D
var _sled_pos: Vector3 = Vector3.ZERO
var _cruise: Array = []
var _cruise_i: int = 0
var _critters: Array = []               # [{node, base_y, phase}] ペンギン/うさぎ ぴょこぴょこ
var _crystals: Array = []               # [{node, base_y, phase, taken}]
var _sfx: AudioStreamPlayer
var _btn_text: String = ""
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
	_btn = root.find_child("YukiButton", true, false) as BaseButton
	if _btn:
		_btn.pressed.connect(_on_pressed)
		_btn.visible = false
	if _env and _env.environment:
		_earth_fog_density = _env.environment.fog_density
		_earth_fog_enabled = _env.environment.fog_enabled
	_ensure_audio()
	_sled_pos = _dock_pos()
	_build_sled()
	_park_sled_at(_sled_pos)


func _process(delta: float) -> void:
	if _player == null or _btn == null or _busy:
		return
	if _on_yuki:
		_drive_cruise(delta)
		_update_critters(delta)
		_update_crystals(delta)
		_set_btn_state("おうちへ かえる")
	else:
		var riding: bool = _ride != null and _ride.has_method("is_riding") and _ride.is_riding()
		var near: bool = (not riding) and _player.global_position.distance_to(_sled_pos) < ENTER_RANGE
		_set_btn_state("ゆきの くにへ いこう" if near else "")


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
	if _on_yuki:
		_return_home()
		return
	if _ride != null and _ride.has_method("is_riding") and _ride.is_riding():
		return
	if _player.global_position.distance_to(_sled_pos) < ENTER_RANGE:
		_depart()


# === 行く / 帰る ===

func _depart() -> void:
	_busy = true
	_hide_btn()
	if not _world_built:
		_build_yuki_world()
		_world_built = true
	_transition(_arrive_yuki_mid, _arrive_yuki_done)


func _return_home() -> void:
	_busy = true
	_hide_btn()
	_transition(_arrive_home_mid, _arrive_home_done)


func _arrive_yuki_mid() -> void:
	_on_yuki = true
	_begin_ride()
	_cruise_i = 0
	if not _cruise.is_empty():
		_player.global_position = _cruise[0]
	_player.velocity = Vector3.ZERO
	_snap_cam()
	_apply_yuki_env()
	if _gs and _gs.has_method("set_yuki_visited"):
		_gs.set_yuki_visited()


func _arrive_yuki_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ゆきの くにへ!")
	_busy = false


func _arrive_home_mid() -> void:
	_on_yuki = false
	_end_ride()
	var gy: float = TerrainHeight.compute_height(SLED_DOCK.x + 3.0, SLED_DOCK.y)
	_player.global_position = Vector3(SLED_DOCK.x + 3.0, gy + 1.0, SLED_DOCK.y)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_snap_cam()
	_restore_earth_env()


func _arrive_home_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ただいま!")
	_busy = false


func _begin_ride() -> void:
	if _sled.get_parent() != _player:
		if _sled.get_parent():
			_sled.get_parent().remove_child(_sled)
		_player.add_child(_sled)
	_sled.position = Vector3(0, -0.4, 0)
	_sled.rotation = Vector3.ZERO
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	_player.set("gravity_scale", 0.0)


func _end_ride() -> void:
	_park_sled_at(_dock_pos())
	_player.set_physics_process(true)
	_player.set("gravity_scale", 1.0)


func _park_sled_at(pos: Vector3) -> void:
	if _sled.get_parent():
		_sled.get_parent().remove_child(_sled)
	add_child(_sled)
	_sled.global_position = pos
	_sled.rotation = Vector3.ZERO
	_sled_pos = pos


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
	# プレイヤー本体ごと 進行方向へ向ける(子の そりと 主人公が そろって前を向く)。
	# カメラは位置だけ追従し 向きには影響されないので 酔わない。
	var flat := Vector2(dir.x, dir.z)
	if flat.length() > 0.05:
		var target_yaw: float = atan2(-dir.x, -dir.z)
		_player.rotation.y = lerp_angle(_player.rotation.y, target_yaw, clamp(4.0 * delta, 0.0, 1.0))


func _snap_cam() -> void:
	if _rig and _rig.has_method("snap_to_target"):
		_rig.snap_to_target()


# === 環境(ゆきの くに / 地球) ===

func _apply_yuki_env() -> void:
	if _dn:
		_dn.set("paused", true)
	_set_petals(false)
	if _env and _env.environment:
		var e := _env.environment
		e.background_color = YUKI_SKY
		e.ambient_light_color = Color(0.78, 0.84, 0.95)
		e.ambient_light_energy = 0.75            # 雪あかりで明るい(暗くしない=怖くない)
		e.fog_enabled = true
		e.fog_density = 0.0016
		e.fog_light_color = Color(0.78, 0.86, 0.96)
	if _sun:
		_sun.rotation_degrees = Vector3(-32.0, 30.0, 0.0)   # 低い夕日
		_sun.light_color = Color(1.0, 0.92, 0.86)
		_sun.light_energy = 0.95


func _restore_earth_env() -> void:
	if _env and _env.environment:
		_env.environment.fog_density = _earth_fog_density
		_env.environment.fog_enabled = _earth_fog_enabled
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


# === 地上の そり ===

func _dock_pos() -> Vector3:
	var gy: float = TerrainHeight.compute_height(SLED_DOCK.x, SLED_DOCK.y)
	return Vector3(SLED_DOCK.x, gy + 0.5, SLED_DOCK.y)


func _build_sled() -> void:
	_sled = Node3D.new()
	# 座面
	_lbox(_sled, Vector3(1.6, 0.2, 3.0), Vector3(0, 0.7, 0), SLED_RED)
	# せもたれ(うしろ +z)
	_lbox(_sled, Vector3(1.6, 1.0, 0.2), Vector3(0, 1.1, 1.4), SLED_RED)
	# クッション
	_lbox(_sled, Vector3(1.4, 0.18, 2.4), Vector3(0, 0.82, 0), SLED_TRIM)
	# すべる かなぐ(左右の ランナー・前が そり上がる)
	for sx in [-0.7, 0.7]:
		_lbox(_sled, Vector3(0.16, 0.16, 3.2), Vector3(sx, 0.25, 0), SLED_TRIM)
		_lcyl(_sled, 0.14, 0.5, Vector3(sx, 0.45, -1.6), SLED_TRIM, 8).rotation.z = PI * 0.5
		_lbox(_sled, Vector3(0.16, 0.4, 0.16), Vector3(sx, 0.45, -1.6), SLED_TRIM)
		_lbox(_sled, Vector3(0.16, 0.4, 0.16), Vector3(sx, 0.45, 1.4), SLED_TRIM)
	# 前の かざり旗
	_lcyl(_sled, 0.04, 1.2, Vector3(0, 1.3, -1.4), TRUNK, 6)
	_lbox(_sled, Vector3(0.5, 0.3, 0.04), Vector3(0.25, 1.7, -1.4), Color(1.0, 0.85, 0.4))


# === ゆきの くに(遠く、初回のみ生成) ===

func _build_yuki_world() -> void:
	var c := YUKI_POS
	# 雪原(大きな円盤)+ ゆるい雪の丘
	var floor_mi := _lcyl(self, 110.0, 2.0, c + Vector3(0, -1.0, 0), SNOW, 40)
	floor_mi.name = "SnowGround"
	for i in range(10):
		var a: float = float(i) / 10.0 * TAU
		var rr: float = 34.0 + float(i % 3) * 14.0
		var hill := _lsphere(self, 9.0 + float(i % 4) * 3.0, c + Vector3(cos(a) * rr, -1.5, sin(a) * rr), SNOW_DK)
		hill.scale = Vector3(1.0, 0.4, 1.0)
	_build_pines(c)
	_build_snowmen(c)
	_build_igloo(c + Vector3(-22, 0, 14))
	_build_penguins(c)
	_build_bunnies(c)
	_build_hot_spring(c + Vector3(16, 0, -16))
	_build_aurora(c)
	_build_snowfall(c)
	_build_crystals(c)
	# 巡航ルート
	_cruise.clear()
	var n: int = 12
	for i in range(n):
		var a: float = float(i) / float(n) * TAU
		_cruise.append(c + Vector3(cos(a) * CRUISE_R, CRUISE_Y, sin(a) * CRUISE_R))


func _build_pines(c: Vector3) -> void:
	for i in range(12):
		var a: float = float(i) / 12.0 * TAU + 0.2
		var rr: float = 38.0 + float(i % 4) * 10.0
		var base := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		_lcyl(self, 0.4, 1.6, base + Vector3(0, 0.8, 0), TRUNK, 8)
		# 雪をかぶった 三段の もみの木
		for k in range(3):
			var rk: float = 2.2 - float(k) * 0.5
			_lcone(self, rk, 2.2, base + Vector3(0, 2.0 + float(k) * 1.5, 0), PINE)
			_lcone(self, rk * 0.85, 0.5, base + Vector3(0, 2.8 + float(k) * 1.5, 0), SNOW)  # 雪


func _build_snowmen(c: Vector3) -> void:
	var spots: Array[Vector3] = [Vector3(-8, 0, 8), Vector3(12, 0, 10), Vector3(6, 0, -14)]
	for i in range(spots.size()):
		var p := c + spots[i]
		_lsphere(self, 1.3, p + Vector3(0, 1.0, 0), SNOW)         # 体
		_lsphere(self, 0.9, p + Vector3(0, 2.6, 0), SNOW)         # 頭
		# 目・ボタン(炭)
		for sx in [-0.3, 0.3]:
			_lemit(self, 0.1, p + Vector3(sx, 2.8, -0.8), Color(0.12, 0.12, 0.14))
		_lemit(self, 0.1, p + Vector3(0, 1.3, -1.25), Color(0.12, 0.12, 0.14))
		_lemit(self, 0.1, p + Vector3(0, 1.0, -1.3), Color(0.12, 0.12, 0.14))
		# にんじんの 鼻(オレンジ)
		_lcone(self, 0.14, 0.6, p + Vector3(0, 2.6, -1.0), Color(1.0, 0.6, 0.3)).rotation.x = -PI * 0.5
		# えだの 手
		for sx in [-1.0, 1.0]:
			_lcyl(self, 0.05, 1.0, p + Vector3(sx, 1.4, 0), TRUNK, 6).rotation.z = sx * 0.6
		# バケツの ぼうし
		_lcyl(self, 0.45, 0.5, p + Vector3(0, 3.4, 0), Color(0.6, 0.66, 0.72), 12)


func _build_igloo(p: Vector3) -> void:
	# ドーム(半球)+ 入り口トンネル
	var dome := _lsphere(self, 3.0, p + Vector3(0, 0.2, 0), SNOW)
	dome.scale = Vector3(1.0, 0.7, 1.0)
	_lcyl(self, 1.0, 1.6, p + Vector3(0, 0.7, -2.6), SNOW, 14).rotation.x = PI * 0.5
	_lsphere(self, 0.85, p + Vector3(0, 0.7, -3.4), Color(0.4, 0.5, 0.62)).scale = Vector3(1.0, 1.0, 0.5)  # 入口(くらい奥)
	# 雪ブロックの すじ
	for k in range(6):
		var a: float = float(k) / 6.0 * TAU
		_lbox(self, Vector3(0.1, 0.6, 1.0), p + Vector3(cos(a) * 2.8, 1.2, sin(a) * 2.8), SNOW_DK).rotation.y = -a


func _build_penguins(c: Vector3) -> void:
	var spots: Array[Vector3] = [Vector3(-4, 0, -4), Vector3(2, 0, 4), Vector3(-12, 0, -2), Vector3(8, 0, -6), Vector3(0, 0, 10)]
	for i in range(spots.size()):
		var p := c + spots[i] + Vector3(0, 0.9, 0)
		var pg := Node3D.new()
		add_child(pg)
		pg.position = p
		_lcap(pg, 0.5, 1.4, Vector3.ZERO, Color(0.18, 0.2, 0.26))          # 体(黒)
		_lsphere(pg, 0.42, Vector3(0, 0.2, -0.18), Color(0.96, 0.97, 1.0)).scale = Vector3(0.8, 0.9, 0.6)  # おなか白
		# くちばし・目・足(オレンジ)
		_lcone(pg, 0.12, 0.4, Vector3(0, 0.3, -0.5), Color(1.0, 0.65, 0.25)).rotation.x = -PI * 0.5
		for sx in [-0.16, 0.16]:
			_lemit(pg, 0.07, Vector3(sx, 0.5, -0.42), Color(0.1, 0.1, 0.12))
		for sx in [-0.2, 0.2]:
			_lbox(pg, Vector3(0.24, 0.08, 0.4), Vector3(sx, -0.75, -0.1), Color(1.0, 0.65, 0.25))
		# 羽
		for sx in [-0.5, 0.5]:
			_lcap(pg, 0.12, 0.7, Vector3(sx, 0.0, 0.1), Color(0.18, 0.2, 0.26)).rotation.z = sx * 0.4
		_critters.append({"node": pg, "base_y": p.y, "phase": float(i) * 0.7})


func _build_bunnies(c: Vector3) -> void:
	var spots: Array[Vector3] = [Vector3(10, 0, 2), Vector3(-6, 0, 12), Vector3(14, 0, -4), Vector3(-14, 0, 6)]
	for i in range(spots.size()):
		var p := c + spots[i] + Vector3(0, 0.5, 0)
		var b := Node3D.new()
		add_child(b)
		b.position = p
		_lsphere(b, 0.45, Vector3.ZERO, SNOW)                  # 体
		_lsphere(b, 0.32, Vector3(0, 0.45, -0.1), SNOW)        # 頭
		for sx in [-0.12, 0.12]:
			_lcap(b, 0.08, 0.5, Vector3(sx, 0.9, -0.05), SNOW)  # 耳
			_lemit(b, 0.05, Vector3(sx, 0.5, -0.34), Color(0.95, 0.5, 0.6))  # ピンクの目
		_lsphere(b, 0.12, Vector3(0, 0.0, 0.45), SNOW_DK)      # しっぽ
		_critters.append({"node": b, "base_y": p.y, "phase": float(i) * 0.9 + 0.4})


func _update_critters(delta: float) -> void:
	for ct in _critters:
		var node: Node3D = ct["node"]
		ct["phase"] += delta * 2.6
		node.position.y = ct["base_y"] + absf(sin(ct["phase"])) * 0.3


func _build_hot_spring(p: Vector3) -> void:
	# まわりの岩
	for k in range(10):
		var a: float = float(k) / 10.0 * TAU
		_lsphere(self, 0.8, p + Vector3(cos(a) * 3.2, 0.2, sin(a) * 3.2), Color(0.55, 0.55, 0.58)).scale = Vector3(1.0, 0.7, 1.0)
	# お湯(半透明・少し光る)
	var water := _lcyl(self, 3.0, 0.2, p + Vector3(0, 0.3, 0), SPRING_C, 24)
	var wm := water.material_override as StandardMaterial3D
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.emission_enabled = true
	wm.emission = Color(0.7, 0.9, 0.9)
	wm.emission_energy_multiplier = 0.3
	# 湯けむり(上へ)
	_spawn_steam(p + Vector3(0, 0.4, 0))


func _build_aurora(c: Vector3) -> void:
	# 高いところに やさしく光る オーロラの帯(数本・ゆっくり点滅)
	for i in range(4):
		var col: Color = AURORA_COLS[i % AURORA_COLS.size()]
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(60.0, 14.0, 0.5)
		mi.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(col.r, col.g, col.b, 0.25)
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.2
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.position = c + Vector3(float(i - 2) * 16.0, 40.0 + float(i % 2) * 6.0, -50.0)
		mi.rotation = Vector3(0.3, float(i) * 0.2, 0.15)
		add_child(mi)
		# ゆっくり 明るさが ゆれる(やさしい)
		var tw := create_tween().set_loops()
		tw.tween_property(m, "emission_energy_multiplier", 0.5, 2.5 + float(i) * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(m, "emission_energy_multiplier", 1.4, 2.5 + float(i) * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _build_snowfall(c: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 140
	p.lifetime = 7.0
	p.preprocess = 4.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(60.0, 1.0, 60.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0.4, -1.2, 0)     # ゆっくり ふわふわ落ちる
	pm.scale_min = 0.1
	pm.scale_max = 0.24
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.2, 0.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	add_child(p)
	p.global_position = c + Vector3(0, 30, 0)
	p.emitting = true


func _spawn_steam(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 3.0
	p.preprocess = 2.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.4
	pm.scale_max = 0.9
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	add_child(p)
	p.global_position = pos
	p.emitting = true


# === ゆきの クリスタル(ごほうび) ===

func _build_crystals(c: Vector3) -> void:
	var spots: Array[float] = [0.5, 1.6, 2.7, 3.9, 5.1]
	for i in range(spots.size()):
		var a: float = spots[i]
		var p := c + Vector3(cos(a) * (CRUISE_R - 4.0), 1.5, sin(a) * (CRUISE_R - 4.0))
		var mi := _lemit(self, 0.45, p, CRYSTAL_C)
		mi.scale = Vector3(0.7, 1.4, 0.7)
		_crystals.append({"node": mi, "base_y": p.y, "phase": float(i) * 1.1, "taken": false})


func _update_crystals(delta: float) -> void:
	if _crystals.is_empty():
		return
	var pp: Vector3 = _player.global_position
	for cr in _crystals:
		if cr["taken"]:
			continue
		var node: Node3D = cr["node"]
		node.rotate_y(1.2 * delta)
		cr["phase"] += delta * 1.4
		node.position.y = cr["base_y"] + sin(cr["phase"]) * 0.25
		if node.global_position.distance_to(pp) < GET_RANGE:
			_collect_crystal(cr)


func _collect_crystal(cr: Dictionary) -> void:
	cr["taken"] = true
	var node: Node3D = cr["node"]
	_spawn_burst(node.global_position, CRYSTAL_C)
	if _gs and _gs.has_method("add_star"):
		_gs.add_star()
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("クリスタル ゲット!")
	if _player and _player.has_method("celebrate"):
		_player.celebrate()
	if _sfx:
		_sfx.play()
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.1, 2.0, 1.1), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
		_sfx.stream = _make_tone(1047.0, 1568.0, 0.22)   # やさしい きらきら(高め)
		_sfx.volume_db = -6.0
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
