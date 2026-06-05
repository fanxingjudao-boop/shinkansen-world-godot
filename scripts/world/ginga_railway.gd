extends Node3D

# 銀河鉄道(ぎんがてつどう)。星空・天の川を 夢の汽車で 自動運転で めぐる別世界。
# submarine / yuki_land と同じ「乗り物→別世界ワープ + 乗り物を装着して自動巡航」骨格。
# Main.tscn を編集せず main.gd が _spawn_extra で生成(load_steps 据え置き)。
# HUD ボタン(GingaButton)も このスクリプトが実行時に作る(TouchHUD.tscn 不変)。
# おでかけメニュー(world_select.gd の WORLDS に "GingaRailway")からも来られる。
#
# 仕組み:
# - 草原に 光る夢の汽車を駐車。近づくと HUD「ぎんがてつどうに のろう」。
# - 押すと フェード → 星空の銀河へ。プレイヤーを汽車に装着し physics off+gravity0。
#   光るレールの輪を ゆっくり自動巡航(しゅーっと 星の間を)。
# - 星のかけらに近づくと ゲット(ほし)。
# - いる間は「おうちへ かえる」常時表示。いつでも帰れる。
#
# 怖くない配慮(厳守): 真っ暗にしない(深い藍+たくさんの明るい星・大きな月・光るレールで
#   ルミナスに)。急に出てこない・自動運転で安心・失敗/落下なし・やさしい音。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const GINGA_DOCK := Vector2(56.0, 24.0)             # 地上の駐車(草原・他の乗り物と離す)
const GINGA_POS := Vector3(3200.0, 500.0, 3200.0)   # 銀河(遠く・高い空)
const ENTER_RANGE := 10.0
const FADE_TIME := 0.35
const CRUISE_SPEED := 9.0          # 星から星へ ぐんぐん渡っていく
const CRUISE_Y := 2.0
const GALAXY_R := 95.0             # 星々をめぐる大きな輪(渡り歩くイメージ)
const STAR_WAVE_Y := 22.0          # 上下のうねり(立体的に星を渡る)
const STAR_STOPS := 12             # 渡り歩く 大きな星の数
const GET_RANGE := 5.0
# 渡り歩く 大きな星の いろいろな色(すべての星々)
const STAR_STOP_COLS := [
	Color(1.0, 0.95, 0.6), Color(1.0, 0.72, 0.82), Color(0.7, 0.85, 1.0), Color(0.8, 1.0, 0.82),
	Color(1.0, 0.8, 0.5), Color(0.85, 0.76, 1.0), Color(0.7, 1.0, 0.95), Color(1.0, 0.9, 0.78),
]

const SKY_C := Color(0.10, 0.12, 0.32)        # 深い藍(真っ黒にしない=怖くない)
const STAR_C := Color(1.0, 1.0, 0.92)
const MILKY_C := Color(0.72, 0.82, 1.0)
const RAIL_C := Color(0.65, 0.9, 1.0)         # 光るレール
const LOCO_BODY := Color(0.12, 0.32, 0.34)    # 深い緑青(銀河鉄道999 風)
const LOCO_TRIM := Color(1.0, 0.84, 0.42)     # 金のふち
const WIN_GLOW := Color(1.0, 0.95, 0.65)      # 窓のあかり
const CAR_BODY := Color(0.18, 0.22, 0.42)     # 客車(夜の青)
const LANTERN_C := Color(1.0, 0.86, 0.5)
const PIECE_C := Color(1.0, 0.92, 0.5)        # 星のかけら(金)
const PLANET_COLS := [Color(1.0, 0.7, 0.5), Color(0.6, 0.8, 1.0), Color(0.8, 0.7, 1.0), Color(0.7, 0.95, 0.8)]

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

var _on_ginga: bool = false
var _busy: bool = false
var _world_built: bool = false
var _loco: Node3D
var _loco_pos: Vector3 = Vector3.ZERO
var _cruise: Array = []
var _cruise_i: int = 0
var _lanterns: Array = []                # [{node, base_y, phase}]
var _pieces: Array = []                  # [{node, base_y, phase, taken}]
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
	_build_button()
	if _env and _env.environment:
		_earth_fog_density = _env.environment.fog_density
		_earth_fog_enabled = _env.environment.fog_enabled
	_ensure_audio()
	_loco_pos = _dock_pos()
	_build_loco()
	_park_loco_at(_loco_pos)


# HUD の「ぎんがてつどうに のろう / おうちへ かえる」ボタンを実行時に作る(他ワールドと同じ
# 上部中央スロット・ピンク丸ボタン)。TouchHUD.tscn を編集しないための方式。
func _build_button() -> void:
	if _hud == null:
		return
	_btn = Button.new()
	_btn.name = "GingaButton"
	_btn.anchor_left = 0.5
	_btn.anchor_right = 0.5
	_btn.offset_left = -135.0
	_btn.offset_top = 22.0
	_btn.offset_right = 145.0
	_btn.offset_bottom = 102.0
	_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_btn.add_theme_font_size_override("font_size", 28)
	_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.6, 0.55, 0.92)   # ぎんが色(むらさき寄り)
	sb.set_corner_radius_all(28)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0.45, 0.4, 0.78)
	sb2.set_corner_radius_all(28)
	_btn.add_theme_stylebox_override("normal", sb)
	_btn.add_theme_stylebox_override("hover", sb)
	_btn.add_theme_stylebox_override("focus", sb)
	_btn.add_theme_stylebox_override("pressed", sb2)
	_btn.visible = false
	_btn.pressed.connect(_on_pressed)
	_hud.add_child(_btn)


func _process(delta: float) -> void:
	if _player == null or _btn == null or _busy:
		return
	if _on_ginga:
		_drive_cruise(delta)
		_update_lanterns(delta)
		_update_pieces(delta)
		_set_btn_state("おうちへ かえる")
	else:
		var riding: bool = _ride != null and _ride.has_method("is_riding") and _ride.is_riding()
		var near: bool = (not riding) and _player.global_position.distance_to(_loco_pos) < ENTER_RANGE
		_set_btn_state("ぎんがてつどうに のろう" if near else "")


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
	if _on_ginga:
		_return_home()
		return
	if _ride != null and _ride.has_method("is_riding") and _ride.is_riding():
		return
	if _player.global_position.distance_to(_loco_pos) < ENTER_RANGE:
		_depart()


# === 行く / 帰る ===

# おでかけメニューから 直接ワープ(汽車の近くにいなくても)。
func warp_in() -> void:
	if _busy or _on_ginga:
		return
	_depart()


func is_active() -> bool:
	return _on_ginga


func _depart() -> void:
	_busy = true
	_hide_btn()
	if not _world_built:
		_build_galaxy_world()
		_world_built = true
	_transition(_arrive_ginga_mid, _arrive_ginga_done)


func _return_home() -> void:
	_busy = true
	_hide_btn()
	_transition(_arrive_home_mid, _arrive_home_done)


func _arrive_ginga_mid() -> void:
	_on_ginga = true
	_begin_ride()
	_cruise_i = 0
	if not _cruise.is_empty():
		_player.global_position = _cruise[0]
	_player.velocity = Vector3.ZERO
	_snap_cam()
	_apply_ginga_env()
	if _gs and _gs.has_method("set_ginga_visited"):
		_gs.set_ginga_visited()


func _arrive_ginga_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ぎんがてつどう しゅっぱつ!")
	_busy = false


func _arrive_home_mid() -> void:
	_on_ginga = false
	_end_ride()
	var gy: float = TerrainHeight.compute_height(GINGA_DOCK.x + 3.0, GINGA_DOCK.y)
	_player.global_position = Vector3(GINGA_DOCK.x + 3.0, gy + 1.0, GINGA_DOCK.y)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_snap_cam()
	_restore_earth_env()


func _arrive_home_done() -> void:
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ただいま!")
	_busy = false


func _begin_ride() -> void:
	if _loco.get_parent() != _player:
		if _loco.get_parent():
			_loco.get_parent().remove_child(_loco)
		_player.add_child(_loco)
	_loco.position = Vector3(0, -1.1, 0)
	_loco.rotation = Vector3.ZERO
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	_player.set("gravity_scale", 0.0)


func _end_ride() -> void:
	_park_loco_at(_dock_pos())
	_player.set_physics_process(true)
	_player.set("gravity_scale", 1.0)


func _park_loco_at(pos: Vector3) -> void:
	if _loco.get_parent():
		_loco.get_parent().remove_child(_loco)
	add_child(_loco)
	_loco.global_position = pos
	_loco.rotation = Vector3.ZERO
	_loco_pos = pos


func _drive_cruise(delta: float) -> void:
	if _cruise.is_empty():
		return
	var target: Vector3 = _cruise[_cruise_i]
	var to: Vector3 = target - _player.global_position
	var d: float = to.length()
	if d < 1.4:
		_cruise_i = (_cruise_i + 1) % _cruise.size()
		return
	var dir: Vector3 = to / d
	_player.global_position += dir * min(CRUISE_SPEED * delta, d)
	var flat := Vector2(dir.x, dir.z)
	if flat.length() > 0.05:
		var target_yaw: float = atan2(-dir.x, -dir.z)
		_player.rotation.y = lerp_angle(_player.rotation.y, target_yaw, clamp(4.0 * delta, 0.0, 1.0))


func _snap_cam() -> void:
	if _rig and _rig.has_method("snap_to_target"):
		_rig.snap_to_target()


# === 環境(銀河 / 地球)===

func _apply_ginga_env() -> void:
	if _dn:
		_dn.set("paused", true)
	_set_petals(false)
	if _env and _env.environment:
		var e := _env.environment
		e.background_color = SKY_C
		e.ambient_light_color = Color(0.5, 0.55, 0.78)
		e.ambient_light_energy = 0.6        # 暗すぎない(星空でも見える)
		e.fog_enabled = false               # 宇宙は澄んでいる
	if _sun:
		_sun.rotation_degrees = Vector3(-50.0, 20.0, 0.0)
		_sun.light_color = Color(0.8, 0.85, 1.0)
		_sun.light_energy = 0.55            # やわらかい月あかり程度


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


# === 地上の 夢の汽車 ===

func _dock_pos() -> Vector3:
	var gy: float = TerrainHeight.compute_height(GINGA_DOCK.x, GINGA_DOCK.y)
	return Vector3(GINGA_DOCK.x, gy + 0.8, GINGA_DOCK.y)


# 銀河鉄道999 風の汽車(機関車 + 客車)。プレイヤーに装着して乗る。
func _build_loco() -> void:
	_loco = Node3D.new()
	# === 機関車(前・-Z 向き)===
	# ボイラー(横向き円柱)
	var boiler := _lcyl(_loco, 0.7, 3.0, Vector3(0, 1.1, -1.2), LOCO_BODY, 16)
	boiler.rotation.x = PI * 0.5
	# 前面(まる)
	_lsphere(_loco, 0.72, Vector3(0, 1.1, -2.7), LOCO_BODY)
	# えんとつ
	_lcyl(_loco, 0.22, 0.7, Vector3(0, 1.9, -2.1), Color(0.1, 0.12, 0.16), 12)
	_lcyl(_loco, 0.3, 0.18, Vector3(0, 2.25, -2.1), LOCO_TRIM, 12)
	# ドーム
	_lsphere(_loco, 0.3, Vector3(0, 1.85, -1.0), LOCO_TRIM).scale = Vector3(1, 0.7, 1)
	# 運転室(うしろ)
	_lbox(_loco, Vector3(1.5, 1.4, 1.4), Vector3(0, 1.4, 0.7), LOCO_BODY)
	_lbox(_loco, Vector3(1.6, 0.2, 1.5), Vector3(0, 2.2, 0.7), LOCO_TRIM)  # 屋根のふち
	# 運転室の窓(光る)
	_lwin(_loco, Vector3(0.05, 0.6, 0.6), Vector3(-0.78, 1.5, 0.7))
	_lwin(_loco, Vector3(0.05, 0.6, 0.6), Vector3(0.78, 1.5, 0.7))
	# ヘッドライト(前・光る)
	_lemit(_loco, 0.18, Vector3(0, 1.3, -2.9), WIN_GLOW)
	# 排障器(カウキャッチャー)
	_lcone(_loco, 0.5, 0.7, Vector3(0, 0.5, -2.6), LOCO_TRIM).rotation.x = -PI * 0.5
	# 動輪(金のふち)
	for sx in [-0.78, 0.78]:
		for wz in [-1.6, -0.6, 0.5]:
			var w := _lcyl(_loco, 0.42, 0.16, Vector3(sx, 0.45, wz), Color(0.1, 0.12, 0.16), 14)
			w.rotation.z = PI * 0.5
			var rim := _lcyl(_loco, 0.2, 0.18, Vector3(sx, 0.45, wz), LOCO_TRIM, 12)
			rim.rotation.z = PI * 0.5
	# === 客車(うしろ +Z)===
	_lbox(_loco, Vector3(1.5, 1.5, 2.6), Vector3(0, 1.3, 2.9), CAR_BODY)
	_lbox(_loco, Vector3(1.6, 0.18, 2.7), Vector3(0, 2.15, 2.9), LOCO_TRIM)  # 屋根ふち
	# 客車の光る窓(両側・3つずつ)
	for sx in [-0.78, 0.78]:
		for wz in [2.1, 2.9, 3.7]:
			_lwin(_loco, Vector3(0.05, 0.5, 0.5), Vector3(sx, 1.35, wz))
	# 連結部
	_lbox(_loco, Vector3(0.4, 0.4, 0.5), Vector3(0, 1.0, 1.6), Color(0.1, 0.12, 0.16))
	# 客車の車輪
	for sx in [-0.78, 0.78]:
		for wz in [2.2, 3.6]:
			var cw := _lcyl(_loco, 0.34, 0.14, Vector3(sx, 0.5, wz), Color(0.1, 0.12, 0.16), 12)
			cw.rotation.z = PI * 0.5
	# ぜんたいを ちょっと光らせる ほし飾り(屋根の上)
	_lemit(_loco, 0.12, Vector3(0, 2.4, 2.9), PIECE_C)


# 光る窓(小さな emissive 板)
func _lwin(parent: Node3D, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = WIN_GLOW
	m.emission_enabled = true
	m.emission = WIN_GLOW
	m.emission_energy_multiplier = 1.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# === 銀河の世界(遠く、初回のみ生成)===

func _build_galaxy_world() -> void:
	var c := GINGA_POS
	_build_starfield(c)
	_build_milkyway(c)
	_build_moon(c)
	_build_planets(c)
	_build_journey(c)   # 大きな星々を 渡り歩く 旅路(レール+巡航+星のかけら)
	_build_lanterns(c)


# たくさんの星(MultiMesh で 1 draw call)。大きなドーム状に散らす。
func _build_starfield(c: Vector3) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 6
	sphere.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = STAR_C
	m.emission_enabled = true
	m.emission = STAR_C
	m.emission_energy_multiplier = 2.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	var count: int = 180
	mm.instance_count = count
	for i in range(count):
		# ドーム状(上半球寄り)に散らす
		var a: float = randf() * TAU
		var el: float = randf_range(-0.2, 1.0)
		var rad: float = randf_range(70.0, 150.0)
		var horiz: float = sqrt(maxf(1.0 - el * el, 0.0))
		var pos := Vector3(cos(a) * horiz * rad, el * rad + 20.0, sin(a) * horiz * rad)
		var s: float = randf_range(0.3, 1.1)
		var tr := Transform3D(Basis().scaled(Vector3(s, s, s)), pos)
		mm.set_instance_transform(i, tr)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = c
	add_child(mmi)


# 天の川(うすく光る帯・大きな板を数枚)
func _build_milkyway(c: Vector3) -> void:
	for i in range(3):
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(260.0, 70.0)
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(MILKY_C.r, MILKY_C.g, MILKY_C.b, 0.12)
		m.emission_enabled = true
		m.emission = MILKY_C
		m.emission_energy_multiplier = 0.5
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mi.material_override = m
		mi.position = c + Vector3(0, 60.0 + float(i) * 8.0, -90.0)
		mi.rotation = Vector3(1.2, float(i) * 0.3, 0.4 + float(i) * 0.15)
		add_child(mi)


func _build_moon(c: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 12.0
	s.height = 24.0
	s.radial_segments = 24
	s.rings = 16
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.97, 0.85)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.96, 0.8)
	m.emission_energy_multiplier = 0.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = c + Vector3(-70.0, 55.0, -80.0)
	add_child(mi)


func _build_planets(c: Vector3) -> void:
	# 惑星は 旅路(輪 半径 95)の外の 遠景に置く(汽車の通り道と重ならない)。
	var spots: Array[Vector3] = [Vector3(155, 70, -120), Vector3(-165, 55, 95), Vector3(120, 100, 150)]
	for i in range(spots.size()):
		var col: Color = PLANET_COLS[i % PLANET_COLS.size()]
		var r: float = 7.0 + float(i % 3) * 4.0
		var pl := _lsphere(self, r, c + spots[i], col)
		var pm := pl.material_override as StandardMaterial3D
		pm.emission_enabled = true
		pm.emission = col
		pm.emission_energy_multiplier = 0.25
	# 輪のある惑星(土星っぽい)
	var saturn := _lsphere(self, 10.0, c + Vector3(-140, 85, 135), Color(0.95, 0.85, 0.6))
	var sm := saturn.material_override as StandardMaterial3D
	sm.emission_enabled = true
	sm.emission = Color(0.95, 0.85, 0.6)
	sm.emission_energy_multiplier = 0.25
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 11.0
	tm.outer_radius = 16.0
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.95, 0.85, 0.6, 0.7)
	rm.emission_enabled = true
	rm.emission = Color(0.95, 0.85, 0.6)
	rm.emission_energy_multiplier = 0.3
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.position = c + Vector3(-140, 85, 135)
	ring.rotation = Vector3(1.1, 0.0, 0.3)
	add_child(ring)


# 星から星へ 渡り歩く 旅路。大きな星を 12 個 大きな輪(上下にうねる)に並べ、
# その間を 光るレール(点の連なり)でつなぐ。汽車は 星のそばを 次々に通っていく。
func _build_journey(c: Vector3) -> void:
	_cruise.clear()
	var n: int = STAR_STOPS
	var wp: Array = []
	for i in range(n):
		var a: float = float(i) / float(n) * TAU
		var rad: float = GALAXY_R + sin(a * 3.0) * 16.0          # 輪を ゆらして 単調にしない
		var y: float = CRUISE_Y + sin(a * 2.0) * STAR_WAVE_Y      # 上下にうねる(立体的)
		var p := c + Vector3(cos(a) * rad, y, sin(a) * rad)
		wp.append(p)
		_cruise.append(p)
		# 大きな星は 進路の すぐ外側に置く(汽車は そのそばを 通り過ぎる=渡り歩く)
		var outward := Vector3(cos(a), 0.0, sin(a))
		_build_big_star(p + outward * 8.0 + Vector3(0, 3.0, 0), i)

	# 光るレール(隣りあう星のあいだを 点の連なりで)。MultiMesh で 1 draw call。
	var dots: Array = []
	for i in range(n):
		var p0: Vector3 = wp[i]
		var p1: Vector3 = wp[(i + 1) % n]
		for k in range(5):
			dots.append(p0.lerp(p1, float(k) / 5.0) + Vector3(0, -0.7, 0))
		# 区間の まんなかに 星のかけら(ごほうび)を ときどき置く
		if i % 2 == 0:
			var mid: Vector3 = p0.lerp(p1, 0.5) + Vector3(0, 0.6, 0)
			var pc := _lemit(self, 0.5, mid, PIECE_C)
			pc.scale = Vector3(1.0, 1.4, 1.0)
			_pieces.append({"node": pc, "base_y": mid.y, "phase": float(i) * 1.1, "taken": false})
	_build_rail_dots(dots)


func _build_rail_dots(dots: Array) -> void:
	if dots.is_empty():
		return
	var s := SphereMesh.new()
	s.radius = 0.22
	s.height = 0.44
	s.radial_segments = 6
	s.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = RAIL_C
	m.emission_enabled = true
	m.emission = RAIL_C
	m.emission_energy_multiplier = 1.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = s
	mm.instance_count = dots.size()
	for j in range(dots.size()):
		mm.set_instance_transform(j, Transform3D(Basis(), dots[j]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


# 渡り歩く 大きな星(光る玉 + うすい光のかさ + ゆっくり またたく)。
func _build_big_star(pos: Vector3, i: int) -> void:
	var col: Color = STAR_STOP_COLS[i % STAR_STOP_COLS.size()]
	var r: float = 2.6 + float(i % 3) * 0.6
	var core := _lemit(self, r, pos, col)
	var cm := core.material_override as StandardMaterial3D
	cm.emission_energy_multiplier = 2.2
	# うすい 光のかさ(半透明・大きめ)
	var halo := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = r * 1.8
	hs.height = r * 3.6
	hs.radial_segments = 12
	hs.rings = 6
	halo.mesh = hs
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(col.r, col.g, col.b, 0.18)
	hm.emission_enabled = true
	hm.emission = col
	hm.emission_energy_multiplier = 0.6
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.material_override = hm
	halo.position = pos
	add_child(halo)
	# ゆっくり またたく(やさしい)
	var tw := create_tween().set_loops()
	var dur: float = 1.6 + float(i % 4) * 0.3
	tw.tween_property(cm, "emission_energy_multiplier", 1.2, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cm, "emission_energy_multiplier", 2.6, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ふわふわ浮かぶ 光のランタン(銀河鉄道の夜)
func _build_lanterns(c: Vector3) -> void:
	for i in range(10):
		var a: float = float(i) / 10.0 * TAU + 0.3
		var rr: float = 40.0 + float(i % 3) * 8.0
		var p := c + Vector3(cos(a) * rr, 6.0 + float(i % 4) * 3.0, sin(a) * rr)
		var mi := _lemit(self, 0.5, p, LANTERN_C)
		_lanterns.append({"node": mi, "base_y": p.y, "phase": float(i) * 0.6})


func _update_lanterns(delta: float) -> void:
	for lt in _lanterns:
		var node: Node3D = lt["node"]
		lt["phase"] += delta * 1.1
		node.position.y = lt["base_y"] + sin(lt["phase"]) * 0.8


# === 星のかけら(ごほうび。旅路の途中に置く。_build_journey で生成)===

func _update_pieces(delta: float) -> void:
	if _pieces.is_empty():
		return
	var pp: Vector3 = _player.global_position
	for pc in _pieces:
		if pc["taken"]:
			continue
		var node: Node3D = pc["node"]
		node.rotate_y(1.4 * delta)
		pc["phase"] += delta * 1.5
		node.position.y = pc["base_y"] + sin(pc["phase"]) * 0.3
		if node.global_position.distance_to(pp) < GET_RANGE:
			_collect_piece(pc)


func _collect_piece(pc: Dictionary) -> void:
	pc["taken"] = true
	var node: Node3D = pc["node"]
	_spawn_burst(node.global_position, PIECE_C)
	if _gs and _gs.has_method("add_star"):
		_gs.add_star()
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ほしの かけら ゲット!")
	if _player and _player.has_method("celebrate"):
		_player.celebrate()
	if _sfx:
		_sfx.play()
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.4, 2.0, 1.4), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	pm.gravity = Vector3(0, -1.0, 0)
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
		_sfx.stream = _make_tone(1175.0, 1760.0, 0.24)   # やさしい きらきら
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


# === メッシュ ヘルパー(parent を渡す)===

func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.1
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
	mi.material_override = _mat(color, 0.6)
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


func _lemit(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi
