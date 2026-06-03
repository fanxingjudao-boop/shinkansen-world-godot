extends Node3D

# サファリカーで「きょうりゅうランド」を 自動運転で めぐる。Main 直下のノード。
# submarine と同じ「乗り物→別世界ワープ + 乗り物を装着して自動巡航」骨格。
#
# 仕組み:
# - 草原に かわいい サファリカーを駐車。近づくと HUD `DinoButton`「きょうりゅうランドへ いこう」。
# - 押すと フェード → 遠くの「きょうりゅうランド」へ。プレイヤーをサファリカーに装着し
#   `set_physics_process(false)`+gravity0。**やさしい きょうりゅう**の間を ゆっくり自動巡航。
# - めぐる間に たまごが かえって あかちゃん恐竜が でてくる(ごほうび)。
# - くにに いる間は「おうちへ かえる」を常時表示。いつでも帰れる。
#
# 怖くない配慮(厳守): 明るい昼の草原・**草食のやさしい恐竜だけ**(ティラノ/牙/襲う系なし)・
# 大きな声を出さない(やさしい鳴き声)・急に出てこない・自動運転で安心・失敗/落下なし。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const SAFARI_DOCK := Vector2(8.0, -58.0)            # 地上の駐車(草原・他の乗り物と離す)
const DINO_POS := Vector3(2600.0, 60.0, 0.0)        # きょうりゅうランド(遠く・地面が DINO_POS.y)
const ENTER_RANGE := 10.0
const FADE_TIME := 0.35
const CRUISE_SPEED := 3.4            # 自動巡航(ゆっくり=酔わない)
const CRUISE_Y := 2.4                # 地面から サファリカーの高さ
const CRUISE_R := 28.0               # 巡航ループ半径
const EGG_GET_RANGE := 4.0

const DINO_SKY := Color(0.6, 0.82, 0.95)
const GROUND := Color(0.52, 0.64, 0.32)
const GROUND_DK := Color(0.44, 0.56, 0.27)
const LEAF := Color(0.3, 0.62, 0.33)
const LEAF_LT := Color(0.46, 0.75, 0.4)
const TRUNK := Color(0.5, 0.36, 0.24)
const BELLY := Color(0.95, 0.92, 0.8)
const CAR_BODY := Color(0.9, 0.78, 0.45)   # サファリ色(カーキ寄りの明るい黄)
const CAR_TRIM := Color(0.45, 0.36, 0.26)
const EGG_C := Color(1.0, 0.95, 0.82)
const DINO_COLS := [Color(0.55, 0.78, 0.55), Color(0.5, 0.78, 0.78), Color(0.95, 0.74, 0.5), Color(0.74, 0.68, 0.95), Color(0.95, 0.86, 0.5)]

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

var _on_dino: bool = false
var _busy: bool = false
var _world_built: bool = false
var _car: Node3D
var _wheels: Array = []                 # 飾りの車輪(回す)
var _car_pos: Vector3 = Vector3.ZERO    # 地上の駐車位置(近接判定)
var _cruise: Array = []                 # 巡航 waypoint(Vector3)
var _cruise_i: int = 0
var _babies: Array = []                 # [{node, base_y, phase}] ぴょこぴょこ
var _eggs: Array = []                   # [{node, base_y, phase, taken, col}]
var _sfx: AudioStreamPlayer
var _btn_text: String = ""
var _call_timer: float = 0.0
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
	_btn = root.find_child("DinoButton", true, false) as BaseButton
	if _btn:
		_btn.pressed.connect(_on_pressed)
		_btn.visible = false
	if _env and _env.environment:
		_earth_fog_density = _env.environment.fog_density
		_earth_fog_enabled = _env.environment.fog_enabled
	_ensure_audio()
	# きょうりゅうランド(遠く)は初回ワープ時に作る。地上の サファリカーは最初から。
	_car_pos = _dock_pos()
	_build_car()
	_park_car_at(_car_pos)


func _process(delta: float) -> void:
	for w in _wheels:
		(w as Node3D).rotate_x(delta * (6.0 if _on_dino else 0.0))
	if _player == null or _btn == null or _busy:
		return
	if _on_dino:
		_drive_cruise(delta)
		_update_babies(delta)
		_update_eggs(delta)
		_call_timer -= delta
		if _call_timer <= 0.0:
			_call_timer = 6.0
			if _sfx:
				_sfx.play()
		_set_btn_state("おうちへ かえる")
	else:
		var riding: bool = _ride != null and _ride.has_method("is_riding") and _ride.is_riding()
		var near: bool = (not riding) and _player.global_position.distance_to(_car_pos) < ENTER_RANGE
		_set_btn_state("きょうりゅうランドへ いこう" if near else "")


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
	if _on_dino:
		_return_home()
		return
	if _ride != null and _ride.has_method("is_riding") and _ride.is_riding():
		return
	if _player.global_position.distance_to(_car_pos) < ENTER_RANGE:
		_depart()


# === 行く / 帰る ===

func _depart() -> void:
	_busy = true
	_hide_btn()
	if not _world_built:
		_build_dino_world()
		_world_built = true
	_transition(_arrive_dino_mid, _arrive_dino_done)


func _return_home() -> void:
	_busy = true
	_hide_btn()
	_transition(_arrive_home_mid, _arrive_home_done)


func _arrive_dino_mid() -> void:
	_on_dino = true
	_begin_ride()
	_cruise_i = 0
	if not _cruise.is_empty():
		_player.global_position = _cruise[0]
	_player.velocity = Vector3.ZERO
	_snap_cam()
	_apply_dino_env()
	if _gs and _gs.has_method("set_dino_visited"):
		_gs.set_dino_visited()


func _arrive_dino_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("きょうりゅうランドへ!")
	_busy = false


func _arrive_home_mid() -> void:
	_on_dino = false
	_end_ride()
	var gy: float = TerrainHeight.compute_height(SAFARI_DOCK.x + 3.0, SAFARI_DOCK.y)
	_player.global_position = Vector3(SAFARI_DOCK.x + 3.0, gy + 1.0, SAFARI_DOCK.y)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_snap_cam()
	_restore_earth_env()


func _arrive_home_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ただいま!")
	_busy = false


# サファリカーをプレイヤーに装着し、通常移動を止める(自動巡航のため)。
func _begin_ride() -> void:
	if _car.get_parent() != _player:
		if _car.get_parent():
			_car.get_parent().remove_child(_car)
		_player.add_child(_car)
	_car.position = Vector3(0, -0.4, 0)
	_car.rotation = Vector3.ZERO
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	_player.set("gravity_scale", 0.0)


func _end_ride() -> void:
	_park_car_at(_dock_pos())
	_player.set_physics_process(true)
	_player.set("gravity_scale", 1.0)


func _park_car_at(pos: Vector3) -> void:
	if _car.get_parent():
		_car.get_parent().remove_child(_car)
	add_child(_car)
	_car.global_position = pos
	_car.rotation = Vector3.ZERO
	_car_pos = pos


# 自動巡航: いまの waypoint へ一定速度で進み、着いたら次へ(ループ)。カーは進行方向へ。
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
	# プレイヤー本体ごと 進行方向へ向ける(子の サファリカーと 主人公が そろって前を向く)。
	# カメラは位置だけ追従し 向きには影響されないので 酔わない。
	var flat := Vector2(dir.x, dir.z)
	if flat.length() > 0.05:
		var target_yaw: float = atan2(-dir.x, -dir.z)
		_player.rotation.y = lerp_angle(_player.rotation.y, target_yaw, clamp(4.0 * delta, 0.0, 1.0))


func _snap_cam() -> void:
	if _rig and _rig.has_method("snap_to_target"):
		_rig.snap_to_target()


# === 環境(きょうりゅうランド / 地球) ===

func _apply_dino_env() -> void:
	if _dn:
		_dn.set("paused", true)
	_set_petals(false)
	if _env and _env.environment:
		var e := _env.environment
		e.background_color = DINO_SKY
		e.ambient_light_color = Color(0.85, 0.9, 0.8)
		e.ambient_light_energy = 0.75           # 明るい昼(暗くしない=怖くない)
		e.fog_enabled = true
		e.fog_density = 0.0016                   # ふんわり遠景
		e.fog_light_color = Color(0.7, 0.85, 0.7)
	if _sun:
		_sun.rotation_degrees = Vector3(-58.0, 20.0, 0.0)
		_sun.light_color = Color(1.0, 0.96, 0.85)
		_sun.light_energy = 1.1


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


# === 地上の サファリカー ===

func _dock_pos() -> Vector3:
	var gy: float = TerrainHeight.compute_height(SAFARI_DOCK.x, SAFARI_DOCK.y)
	return Vector3(SAFARI_DOCK.x, gy + 0.6, SAFARI_DOCK.y)


func _build_car() -> void:
	_car = Node3D.new()
	_wheels.clear()
	# 車体(サファリ色)
	_lbox(_car, Vector3(2.4, 1.0, 3.6), Vector3(0, 0.7, 0), CAR_BODY)
	# ボンネット(前 -z)
	_lbox(_car, Vector3(2.2, 0.6, 1.2), Vector3(0, 0.5, -2.1), CAR_BODY)
	# 座席まわり(オープン)
	_lbox(_car, Vector3(2.0, 0.5, 1.4), Vector3(0, 1.15, 0.4), CAR_TRIM)
	# サファリの しま模様(茶)
	for sz in [-0.6, 0.4, 1.2]:
		_lbox(_car, Vector3(2.46, 0.18, 0.3), Vector3(0, 0.9, sz), CAR_TRIM)
	# ロールバー
	for sx in [-0.9, 0.9]:
		_lcyl(_car, 0.08, 1.2, Vector3(sx, 1.7, 0.4), CAR_TRIM, 8)
	_lcyl(_car, 0.08, 2.0, Vector3(0, 2.3, 0.4), CAR_TRIM, 8).rotation.z = PI * 0.5
	# フロントガラス
	_lbox(_car, Vector3(2.0, 0.9, 0.08), Vector3(0, 1.5, -0.4), Color(0.7, 0.85, 0.95)).rotation.x = -0.5
	# ヘッドライト(光る)
	for sx in [-0.7, 0.7]:
		_lemit(_car, 0.18, Vector3(sx, 0.6, -2.7), Color(1.0, 0.95, 0.6))
	# 車輪(大きい・回る)
	for sx in [-1.2, 1.2]:
		for sz in [-1.3, 1.3]:
			var w := _lcyl(_car, 0.55, 0.4, Vector3(sx, 0.45, sz), Color(0.18, 0.18, 0.2), 14)
			w.rotation.z = PI * 0.5
			_wheels.append(w)


# === きょうりゅうランド(遠く、初回のみ生成) ===

func _build_dino_world() -> void:
	var c := DINO_POS
	# 地面(大きな円盤)+ ゆるい丘
	var floor_mi := _lcyl(self, 110.0, 2.0, c + Vector3(0, -1.0, 0), GROUND, 40)
	floor_mi.name = "DinoGround"
	for i in range(10):
		var a: float = float(i) / 10.0 * TAU
		var rr: float = 36.0 + float(i % 3) * 14.0
		var hill := _lsphere(self, 8.0 + float(i % 4) * 3.0, c + Vector3(cos(a) * rr, -1.0, sin(a) * rr), GROUND_DK)
		hill.scale = Vector3(1.0, 0.35, 1.0)
	# ジャングルの木・しだ・岩
	_build_jungle(c)
	# やさしい きょうりゅうたち
	_build_sauropod(c + Vector3(-14, 0, 10), DINO_COLS[0], true)
	_build_sauropod(c + Vector3(16, 0, -12), DINO_COLS[1], false)
	_build_triceratops(c + Vector3(10, 0, 14), DINO_COLS[2])
	_build_triceratops(c + Vector3(-18, 0, -6), DINO_COLS[3])
	_build_stego(c + Vector3(0, 0, -20), DINO_COLS[4])
	_build_stego(c + Vector3(20, 0, 6), DINO_COLS[0])
	# あかちゃん恐竜(ぴょこぴょこ)
	_build_baby(c + Vector3(-6, 0, 2), DINO_COLS[2])
	_build_baby(c + Vector3(4, 0, -6), DINO_COLS[3])
	_build_baby(c + Vector3(-2, 0, -12), DINO_COLS[1])
	# そらを ゆっくり とぶ プテラノドン(やさしい)
	_build_ptero(c + Vector3(0, 26, 0), DINO_COLS[3])
	# たまご(ごほうび)
	_build_eggs(c)
	# 巡航ルート(きょうりゅうの間を ゆるく まわる)
	_cruise.clear()
	var n: int = 12
	for i in range(n):
		var a: float = float(i) / float(n) * TAU
		_cruise.append(c + Vector3(cos(a) * CRUISE_R, CRUISE_Y, sin(a) * CRUISE_R))


func _build_jungle(c: Vector3) -> void:
	# 大きな木(幹+まるい葉のかたまり)
	for i in range(12):
		var a: float = float(i) / 12.0 * TAU + 0.2
		var rr: float = 40.0 + float(i % 4) * 9.0
		var base := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		var h: float = 7.0 + float(i % 3) * 2.0
		_lcyl(self, 0.7, h, base + Vector3(0, h * 0.5, 0), TRUNK, 8)
		for k in range(3):
			_lsphere(self, 3.0 - float(k) * 0.5, base + Vector3(float(k) - 1.0, h + 1.0 + float(k) * 1.2, 0), LEAF if k % 2 == 0 else LEAF_LT)
	# しだ(低い 葉)
	for i in range(16):
		var a: float = float(i) / 16.0 * TAU * 1.6
		var rr: float = 12.0 + float(i % 6) * 4.0
		var base := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		for k in range(5):
			var fa: float = float(k) / 5.0 * TAU
			var frond := _lcone(self, 0.5, 2.2, base + Vector3(cos(fa) * 0.6, 1.0, sin(fa) * 0.6), LEAF_LT)
			frond.rotation.z = cos(fa) * 0.5
			frond.rotation.x = sin(fa) * 0.5
	# 岩
	for i in range(6):
		var a: float = float(i) / 6.0 * TAU + 0.5
		var rr: float = 22.0 + float(i % 3) * 6.0
		var rock := _lsphere(self, 1.8 + float(i % 3) * 0.6, c + Vector3(cos(a) * rr, 0.3, sin(a) * rr), Color(0.56, 0.54, 0.5))
		rock.scale = Vector3(1.0, 0.7, 1.1)


# 首の長い 草食きょうりゅう(やさしい)。walk=true は ゆっくり横切る。
func _build_sauropod(pos: Vector3, col: Color, walk: bool) -> void:
	var d := Node3D.new()
	add_child(d)
	d.position = pos
	# 体(大きな つぶした カプセル)
	var body := _lcap(d, 2.0, 5.0, Vector3(0, 3.0, 0), col)
	body.rotation.x = PI * 0.5
	_lsphere(d, 1.6, Vector3(0, 2.4, 1.6), BELLY).scale = Vector3(1.1, 0.8, 1.0)   # おなか
	# 長い首(球を 重ねて 上へ カーブ)+ 頭
	var neck := Node3D.new()
	neck.position = Vector3(0, 3.4, -2.2)
	d.add_child(neck)
	for k in range(5):
		_lsphere(neck, 0.9 - float(k) * 0.1, Vector3(0, float(k) * 0.9, -float(k) * 0.5), col)
	var head := _lsphere(neck, 0.8, Vector3(0, 4.4, -2.3), col)
	head.scale = Vector3(0.9, 0.8, 1.2)
	for sx in [-0.3, 0.3]:
		_lemit(neck, 0.1, Vector3(sx, 4.6, -2.9), Color(0.1, 0.1, 0.12))   # 目
	# しっぽ(後ろへ 細く)
	for k in range(5):
		_lsphere(d, 0.8 - float(k) * 0.13, Vector3(0, 3.0 - float(k) * 0.2, 2.5 + float(k) * 0.9), col)
	# 足 4 本
	for sx in [-1.1, 1.1]:
		for sz in [-1.4, 1.4]:
			_lcyl(d, 0.55, 2.2, Vector3(sx, 1.1, sz), col, 10)
	# 首を ゆっくり もぐもぐ(やさしい うごき)
	neck.rotation.x = -0.15
	var tw := create_tween().set_loops()
	tw.tween_property(neck, "rotation:x", 0.15, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(neck, "rotation:x", -0.15, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if walk:
		var tw2 := create_tween().set_loops()
		tw2.tween_property(d, "position", pos + Vector3(0, 0, 18), 20.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw2.tween_property(d, "position", pos, 20.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _build_triceratops(pos: Vector3, col: Color) -> void:
	var d := Node3D.new()
	add_child(d)
	d.position = pos
	var body := _lcap(d, 1.3, 3.2, Vector3(0, 1.8, 0.4), col)
	body.rotation.x = PI * 0.5
	_lsphere(d, 1.0, Vector3(0, 1.5, 0.6), BELLY).scale = Vector3(1.1, 0.7, 1.0)
	# 頭 + フリル(つぶした 円盤)+ つの 3 本(やわらかい コーン)
	var head := _lsphere(d, 1.0, Vector3(0, 1.9, -1.9), col)
	head.scale = Vector3(1.0, 0.9, 1.2)
	var frill := _lcyl(d, 1.5, 0.3, Vector3(0, 2.2, -1.3), col, 16)
	frill.rotation.x = PI * 0.5
	frill.scale = Vector3(1.0, 1.2, 1.0)
	_lcone(d, 0.18, 0.8, Vector3(0, 1.6, -2.8), BELLY).rotation.x = -1.2          # 鼻のつの
	for sx in [-0.5, 0.5]:
		_lcone(d, 0.18, 1.0, Vector3(sx, 2.4, -2.4), BELLY).rotation.x = -0.9     # 目の上の つの
		_lemit(d, 0.1, Vector3(sx * 0.7, 2.0, -2.6), Color(0.1, 0.1, 0.12))       # 目
	# しっぽ・足
	_lcap(d, 0.4, 1.6, Vector3(0, 1.6, 2.4), col).rotation.x = PI * 0.5
	for sx in [-0.8, 0.8]:
		for sz in [-0.9, 0.9]:
			_lcyl(d, 0.4, 1.4, Vector3(sx, 0.7, sz), col, 8)


func _build_stego(pos: Vector3, col: Color) -> void:
	var d := Node3D.new()
	add_child(d)
	d.position = pos
	var body := _lcap(d, 1.3, 3.4, Vector3(0, 1.9, 0), col)
	body.rotation.x = PI * 0.5
	_lsphere(d, 0.7, Vector3(0, 1.6, -2.2), col)   # 小さい頭
	for sx in [-0.2, 0.2]:
		_lemit(d, 0.09, Vector3(sx, 1.7, -2.6), Color(0.1, 0.1, 0.12))
	# 背中の プレート(つぶした 三角を 並べる・パステル)
	var plate_col: Color = DINO_COLS[(DINO_COLS.find(col) + 2) % DINO_COLS.size()]
	for k in range(6):
		var pz: float = -1.4 + float(k) * 0.7
		var plate := _lcone(self, 0.7, 1.2, pos + Vector3(0, 3.0, pz), plate_col)
		plate.scale = Vector3(1.0, 1.0, 0.25)
	# しっぽ(先に やわらかい トゲ)+ 足
	_lcap(d, 0.5, 1.8, Vector3(0, 1.7, 2.4), col).rotation.x = PI * 0.5
	for sx in [-0.4, 0.4]:
		_lcone(d, 0.18, 0.7, Vector3(sx, 1.9, 3.4), plate_col)
	for sx in [-0.8, 0.8]:
		for sz in [-1.0, 1.0]:
			_lcyl(d, 0.42, 1.4, Vector3(sx, 0.7, sz), col, 8)


# あかちゃん恐竜(まるくて 大きな目・ぴょこぴょこ)。
func _build_baby(pos: Vector3, col: Color) -> void:
	var d := Node3D.new()
	add_child(d)
	d.position = pos + Vector3(0, 0.7, 0)
	_lsphere(d, 0.6, Vector3.ZERO, col)                       # 体
	_lsphere(d, 0.45, Vector3(0, 0.6, -0.2), col)             # 頭
	for sx in [-0.18, 0.18]:
		_lemit(d, 0.11, Vector3(sx, 0.7, -0.5), Color(0.98, 0.98, 1.0))   # 白目(大きい)
		_lemit(d, 0.06, Vector3(sx, 0.7, -0.58), Color(0.1, 0.1, 0.12))   # 黒目
	# しっぽ・足
	_lcone(d, 0.2, 0.7, Vector3(0, 0.0, 0.6), col).rotation.x = PI * 0.5
	for sx in [-0.25, 0.25]:
		_lcyl(d, 0.16, 0.4, Vector3(sx, -0.4, 0), col, 8)
	_babies.append({"node": d, "base_y": d.position.y, "phase": pos.x + pos.z})


func _update_babies(delta: float) -> void:
	for b in _babies:
		var node: Node3D = b["node"]
		b["phase"] += delta * 3.0
		node.position.y = b["base_y"] + absf(sin(b["phase"])) * 0.5   # ぴょこぴょこ


func _build_ptero(pos: Vector3, col: Color) -> void:
	var p := Node3D.new()
	add_child(p)
	p.position = pos
	_lsphere(p, 0.5, Vector3.ZERO, col)                      # 体
	_lcone(p, 0.25, 1.0, Vector3(0, 0.1, -0.7), col).rotation.x = -1.4   # くちばし
	_lcone(p, 0.2, 0.9, Vector3(0, 0.5, 0.3), col)           # とさか
	for sx in [-1.0, 1.0]:
		var wing := _lcone(p, 1.4, 2.4, Vector3(sx * 1.4, 0, 0), LEAF_LT)
		wing.rotation.z = sx * PI * 0.5
		wing.scale = Vector3(1.0, 1.0, 0.2)
	# ゆっくり 大きく 旋回(高いところを とぶ)
	var tw := create_tween().set_loops()
	tw.tween_property(p, "position", pos + Vector3(24, 4, 18), 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "position", pos + Vector3(-20, 2, -16), 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "position", pos, 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# === たまご(ごほうび・近づくと かえる) ===

func _build_eggs(c: Vector3) -> void:
	# 巡航ループの近くに たまごの巣を 5 個
	var spots: Array[float] = [0.4, 1.5, 2.7, 3.8, 5.0]
	for i in range(spots.size()):
		var a: float = spots[i]
		var p := c + Vector3(cos(a) * (CRUISE_R - 5.0), 1.0, sin(a) * (CRUISE_R - 5.0))
		# 巣(枝)
		_lcyl(self, 1.2, 0.4, p + Vector3(0, -0.5, 0), TRUNK, 12)
		var egg := _lsphere(self, 0.7, p, EGG_C)
		egg.scale = Vector3(0.85, 1.1, 0.85)
		_eggs.append({"node": egg, "base_y": p.y, "phase": float(i) * 1.1, "taken": false, "col": DINO_COLS[i % DINO_COLS.size()]})


func _update_eggs(delta: float) -> void:
	if _eggs.is_empty():
		return
	var pp: Vector3 = _player.global_position
	for eg in _eggs:
		if eg["taken"]:
			continue
		var node: Node3D = eg["node"]
		eg["phase"] += delta * 3.0
		# ゆれて「もうすぐ かえるよ」感
		node.rotation.z = sin(eg["phase"]) * 0.12
		if node.global_position.distance_to(pp) < EGG_GET_RANGE:
			_hatch_egg(eg)


func _hatch_egg(eg: Dictionary) -> void:
	eg["taken"] = true
	var node: Node3D = eg["node"]
	var col: Color = eg["col"]
	var pos: Vector3 = node.global_position
	_spawn_burst(pos, Color(1.0, 0.95, 0.7))
	# あかちゃんが でてくる(self は原点なので ワールド座標=ローカル)
	_build_baby(pos, col)
	if _gs and _gs.has_method("add_star"):
		_gs.add_star()
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("たまご かえった!")
	if _player and _player.has_method("celebrate"):
		_player.celebrate()
	if _sfx:
		_sfx.play()
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 1.5, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ZERO, 0.26)
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
		_sfx.stream = _make_tone(330.0, 247.0, 0.35)   # やさしい「わぁ〜お」(低め・下がる)
		_sfx.volume_db = -8.0
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
