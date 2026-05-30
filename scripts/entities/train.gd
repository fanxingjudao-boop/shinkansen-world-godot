extends Node3D

# class_name は Godot エディタが project をスキャンするまで CLI で
# 認識されないため preload 両対応
const TrainData = preload("res://scripts/entities/train_data.gd")
const Railway = preload("res://scripts/world/railway.gd")

# 列車本体スクリプト。
# - _ready で railway の Path3D を取得し、PathFollow3D を動的に add_child
# - _process で「弧長(実距離)」progress を等速で進める。
#   ※ 旧実装は progress_ratio = 角度t/TAU だったが、楕円+高低差で
#     「角度あたりの実距離」が変動するため坂で急加速/急減速していた。
#     弧長ベースにして線路上を常に一定速度で走るようにした(滑らか)。
# - 見た目は train_data に応じてスクリプトで全部組み立て(5 両編成、個別窓、台車、連結部)

@export var train_data: TrainData
@export var railway_path: NodePath

# === 車両構成定数 ===
const CAR_COUNT: int = 5                  # 5 両編成(LEAD + MID×3 + TAIL)
const LEAD_LENGTH: float = 5.5
const MID_LENGTH: float = 4.5
const COUPLER_LENGTH: float = 0.4         # 連結部の長さ(車両間ジャバラ)
const CAR_WIDTH: float = 1.9
const CAR_HEIGHT: float = 1.5
const CAR_BASE_Y: float = 1.1             # レール面からの車両中心の高さ

const ACCENT_BAND_HEIGHT: float = 0.22
const WINDOW_HEIGHT: float = 0.45
const WINDOW_GAP: float = 0.18            # 窓と窓の間
const WINDOW_PER_LEAD: int = 4            # 先頭/末尾車の窓の数(ノーズ側少なめ)
const WINDOW_PER_MID: int = 6             # 中間車の窓の数
const WHEEL_RADIUS: float = 0.32
const BOGIE_OFFSET_RATIO: float = 0.32    # 車両長に対する台車位置(前後 32%)

const WINDOW_COLOR: Color = Color(0.4, 0.8, 1.0)       # #66ccff
const WHEEL_COLOR: Color = Color(0.13, 0.13, 0.13)
const BOGIE_COLOR: Color = Color(0.25, 0.25, 0.28)     # 台車の濃灰
const COUPLER_COLOR: Color = Color(0.18, 0.18, 0.20)   # 連結部の暗灰
const HEADLIGHT_COLOR: Color = Color(1.0, 1.0, 0.8)

# 駅停車: 駅の track_t 近くで減速(resources/station_data/*.tres の track_t と一致させること)
const STATION_TS: Array = [0.0, 1.0472, 2.0944, 3.1416, 4.1888, 5.236]
const STATION_SLOW_RANGE: float = 0.22   # 駅前後この角度幅で減速
const STATION_MIN_FACTOR: float = 0.25   # 駅中心での速度係数(25%)

var _path_follow: PathFollow3D
var _progress: float = 0.0          # 線路上の現在位置(弧長, メートル)
var _length: float = 0.0            # 線路一周の弧長
var _linear_speed: float = 0.0      # 実速度(m/s)。旧角速度から周回時間を保つよう換算
var _station_offsets: PackedFloat32Array = PackedFloat32Array()  # 各駅の弧長オフセット
var _station_range_m: float = 0.0   # 駅減速の範囲(メートル)


func _ready() -> void:
	if train_data == null:
		push_warning("[Train] train_data が未設定")
		return
	if railway_path.is_empty():
		push_warning("[Train] railway_path が未設定")
		return
	var path_node := get_node_or_null(railway_path) as Path3D
	if path_node == null:
		push_warning("[Train] railway_path の参照先が Path3D でない")
		return
	_path_follow = PathFollow3D.new()
	_path_follow.loop = true
	_path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	var visual := _build_visual()
	_path_follow.add_child(visual)
	path_node.add_child(_path_follow)

	# 弧長ベースの移動を準備
	var curve := path_node.curve
	_length = curve.get_baked_length()
	# 旧: 一周 = TAU/speed 秒。新: 一周 = _length/_linear_speed 秒。周回時間を一致させる。
	_linear_speed = train_data.speed * _length / TAU
	_station_range_m = _length * STATION_SLOW_RANGE / TAU
	# 初期位置(角度)を弧長オフセットへ変換
	var ip: Vector2 = Railway.ellipse_point(train_data.initial_t)
	_progress = curve.get_closest_offset(Vector3(ip.x, 0.0, ip.y))
	# 各駅の弧長オフセットを事前計算(減速判定に使う)
	for st in STATION_TS:
		var sp: Vector2 = Railway.ellipse_point(st)
		_station_offsets.append(curve.get_closest_offset(Vector3(sp.x, 0.0, sp.y)))

	_path_follow.progress = _progress


func _process(delta: float) -> void:
	if _path_follow == null or train_data == null or _length <= 0.0:
		return
	var factor: float = _slow_factor_at(_progress)
	_progress = fposmod(_progress + _linear_speed * factor * delta, _length)
	_path_follow.progress = _progress


# === ロジック層 ===

# 現在の弧長位置が駅に近いほど速度係数を STATION_MIN_FACTOR まで落とす(駅でゆっくり通過)。
# 複数駅が近い場合は最も遅い係数を採用。距離は周回のラップを考慮。
func _slow_factor_at(progress: float) -> float:
	var factor: float = 1.0
	for off in _station_offsets:
		var d: float = absf(_wrap_dist(progress, off))
		if d < _station_range_m:
			factor = minf(factor, lerpf(STATION_MIN_FACTOR, 1.0, d / _station_range_m))
	return factor


# 閉路上の符号付き最短距離(メートル)
func _wrap_dist(a: float, b: float) -> float:
	var d: float = fposmod(a - b, _length)
	if d > _length * 0.5:
		d -= _length
	return d


# === 乗車システム用 public API(RideController から呼ばれる) ===

# 編成中央の現在ワールド位置(乗車判定の距離計算・降車位置の基準に使う)
func get_ride_anchor_position() -> Vector3:
	if _path_follow == null:
		return global_position
	return _path_follow.global_position

# カメラをぶら下げる先(PathFollow3D 自身)。
# PathFollow3D は ROTATION_ORIENTED なので、この子に置いたカメラは
# 進行方向に自動追従し、ローカル固定 transform なら一切揺れない。
func get_ride_mount() -> Node3D:
	return _path_follow

# 編成中央の現在の進行方向(ワールド)。-Z が進行方向(先頭)。
func get_ride_forward() -> Vector3:
	if _path_follow == null:
		return -global_transform.basis.z
	return -_path_follow.global_transform.basis.z

# 表示名(ひらがな)。プロンプト・通知用。
func get_display_name() -> String:
	return train_data.display_name if train_data else ""

# 内部識別子(図鑑の発見記録用)
func get_slug() -> String:
	return train_data.slug if train_data else ""


# === メッシュ構築(Godot 操作層) ===

func _build_visual() -> Node3D:
	var root := Node3D.new()

	# 各車両の長さリスト(LEAD + MID×3 + TAIL)
	var lengths: Array = [LEAD_LENGTH, MID_LENGTH, MID_LENGTH, MID_LENGTH, LEAD_LENGTH]
	var roles: Array = ["lead", "mid", "mid", "mid", "tail"]

	# 編成全体の中心が PathFollow3D の原点に来るように Z オフセットを計算
	# PathFollow3D ローカル: -Z が進行方向(先頭)
	var total_length: float = 0.0
	for l in lengths:
		total_length += l
	total_length += COUPLER_LENGTH * (CAR_COUNT - 1)

	# 先頭から末尾へ累積 Z 配置(進行方向は -Z なので、先頭の中心は -front_z)
	var cursor_z: float = -total_length * 0.5  # 一番手前(進行方向側)から開始
	for i in range(CAR_COUNT):
		var car_len: float = lengths[i]
		var role: String = roles[i]
		# 車両中心の Z 位置
		var car_center_z: float = cursor_z + car_len * 0.5
		var car := _build_car(car_len, role)
		car.position = Vector3(0, CAR_BASE_Y, car_center_z)
		if role == "tail":
			car.rotate_y(PI)  # 末尾車は逆向き
		root.add_child(car)
		cursor_z += car_len

		# 次の車両の前に連結部を配置
		if i < CAR_COUNT - 1:
			var coupler := _build_coupler()
			coupler.position = Vector3(0, CAR_BASE_Y - 0.15, cursor_z + COUPLER_LENGTH * 0.5)
			root.add_child(coupler)
			cursor_z += COUPLER_LENGTH

	return root


func _build_car(car_len: float, role: String) -> Node3D:
	var car := Node3D.new()

	# 本体(BoxMesh)
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(CAR_WIDTH, CAR_HEIGHT, car_len)
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = body_mesh
	body_mi.material_override = _make_material(train_data.body_color, 0.45)
	car.add_child(body_mi)

	# アクセント帯(本体の側面)
	var accent_mesh := BoxMesh.new()
	accent_mesh.size = Vector3(CAR_WIDTH + 0.04, ACCENT_BAND_HEIGHT, car_len - 0.2)
	var accent_mi := MeshInstance3D.new()
	accent_mi.mesh = accent_mesh
	accent_mi.material_override = _make_material(train_data.accent_color, 0.35)
	accent_mi.position = Vector3(0, 0.05, 0)
	car.add_child(accent_mi)

	# 個別の小窓(両側面、5-6 個)
	var window_count: int = WINDOW_PER_MID if role == "mid" else WINDOW_PER_LEAD
	_attach_windows(car, car_len, window_count)

	# 台車(各車両 2 台、前後)
	_attach_bogie(car, car_len, +1.0)
	_attach_bogie(car, car_len, -1.0)

	# 役割別パーツ
	if role == "lead" or role == "tail":
		_attach_nose_and_headlight(car, car_len)
	elif role == "mid" and train_data.has_pantograph:
		_attach_pantograph(car)

	return car


func _attach_windows(car: Node3D, car_len: float, count: int) -> void:
	var window_zone: float = car_len - 1.4  # 両端を残して窓を配置する範囲
	var window_width: float = (window_zone - WINDOW_GAP * (count - 1)) / float(count)
	var start_z: float = -window_zone * 0.5
	for i in range(count):
		var center_z: float = start_z + window_width * 0.5 + i * (window_width + WINDOW_GAP)
		for side in [1.0, -1.0]:
			var w := BoxMesh.new()
			w.size = Vector3(0.04, WINDOW_HEIGHT, window_width)
			var mi := MeshInstance3D.new()
			mi.mesh = w
			mi.material_override = _make_unshaded_material(WINDOW_COLOR)
			mi.position = Vector3(side * (CAR_WIDTH * 0.5 + 0.01), 0.18, center_z)
			car.add_child(mi)


func _attach_bogie(car: Node3D, car_len: float, side_z: float) -> void:
	var bogie_z: float = side_z * car_len * BOGIE_OFFSET_RATIO
	var bogie_y: float = -CAR_HEIGHT * 0.5 - 0.1

	# 台車枠(BoxMesh)
	var frame := BoxMesh.new()
	frame.size = Vector3(1.7, 0.3, 1.4)
	var frame_mi := MeshInstance3D.new()
	frame_mi.mesh = frame
	frame_mi.material_override = _make_material(BOGIE_COLOR, 0.6)
	frame_mi.position = Vector3(0, bogie_y, bogie_z)
	car.add_child(frame_mi)

	# 車輪 4 個(台車の四隅)
	for wx in [0.75, -0.75]:
		for wz_offset in [0.5, -0.5]:
			var wheel := _build_wheel()
			wheel.position = Vector3(wx, bogie_y - 0.1, bogie_z + wz_offset)
			car.add_child(wheel)


func _build_wheel() -> Node3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = WHEEL_RADIUS
	cyl.bottom_radius = WHEEL_RADIUS
	cyl.height = 0.18
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = _make_material(WHEEL_COLOR, 0.7)
	mi.rotate_z(PI * 0.5)  # 横向き(X 軸方向に回転)
	return mi


func _build_coupler() -> Node3D:
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 0.7, COUPLER_LENGTH)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = _make_material(COUPLER_COLOR, 0.6)
	return mi


func _attach_nose_and_headlight(car: Node3D, car_len: float) -> void:
	# ノーズは先端(-Z 方向)に取り付ける(車両長 / 2 から外側へ)
	var nose_base_z: float = -car_len * 0.5
	var nose := _build_nose(train_data.nose_type, nose_base_z)
	car.add_child(nose)

	# ヘッドライト(sharp/rounded のみ、steam は省略)
	if train_data.nose_type != "steam":
		# ノーズの先端より少し手前に配置
		var hl_z: float = nose_base_z - 2.4
		for x in [-0.45, 0.45]:
			var hl := SphereMesh.new()
			hl.radius = 0.13
			hl.height = 0.26
			hl.radial_segments = 8
			hl.rings = 4
			var hl_mi := MeshInstance3D.new()
			hl_mi.mesh = hl
			hl_mi.material_override = _make_emission_material(HEADLIGHT_COLOR)
			hl_mi.position = Vector3(x, -0.25, hl_z)
			car.add_child(hl_mi)


# ノーズを先細りの CylinderMesh(横向き)で表現。
# base_z: 車両本体の先端 Z 座標(ノーズはここから -Z 方向へ伸びる)
func _build_nose(nose_type: String, base_z: float) -> Node3D:
	var nose := Node3D.new()
	if nose_type == "sharp":
		# はやぶさ風のロングノーズ: 円柱を横向きにして top_radius を細く
		var cone := CylinderMesh.new()
		cone.top_radius = 0.12
		cone.bottom_radius = 0.92
		cone.height = 3.2
		cone.radial_segments = 16
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = _make_material(train_data.body_color, 0.45)
		# X 軸周りに -90°回転で水平、頂点が -Z 方向
		mi.rotate_x(-PI * 0.5)
		# CylinderMesh は原点中心 → 半分先に押し出して base_z より外側へ
		mi.position = Vector3(0, 0.0, base_z - cone.height * 0.5)
		# 上下を少し潰して新幹線らしいシルエット
		mi.scale = Vector3(1.0, 1.5, 1.0)
		nose.add_child(mi)
	elif nose_type == "rounded":
		# N700 風のカモノハシ型: 短く太いコーン
		var cone := CylinderMesh.new()
		cone.top_radius = 0.55
		cone.bottom_radius = 0.95
		cone.height = 2.2
		cone.radial_segments = 16
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = _make_material(train_data.body_color, 0.45)
		mi.rotate_x(-PI * 0.5)
		mi.position = Vector3(0, 0.0, base_z - cone.height * 0.5)
		mi.scale = Vector3(1.0, 1.35, 1.0)
		nose.add_child(mi)
		# 先端に丸み
		var tip := SphereMesh.new()
		tip.radius = 0.55
		tip.height = 1.1
		tip.radial_segments = 10
		tip.rings = 6
		var tip_mi := MeshInstance3D.new()
		tip_mi.mesh = tip
		tip_mi.material_override = _make_material(train_data.body_color, 0.45)
		tip_mi.position = Vector3(0, 0.0, base_z - cone.height + 0.1)
		tip_mi.scale = Vector3(1.0, 1.3, 0.8)
		nose.add_child(tip_mi)
	elif nose_type == "steam":
		# SL: ボイラー(横向き円柱)+ 煙突
		var boiler := CylinderMesh.new()
		boiler.top_radius = 0.85
		boiler.bottom_radius = 0.85
		boiler.height = 1.8
		boiler.radial_segments = 16
		var boiler_mi := MeshInstance3D.new()
		boiler_mi.mesh = boiler
		boiler_mi.material_override = _make_material(train_data.body_color, 0.75)
		boiler_mi.rotate_x(-PI * 0.5)
		boiler_mi.position = Vector3(0, 0.0, base_z - boiler.height * 0.5)
		nose.add_child(boiler_mi)
		# 煙突
		var stack := CylinderMesh.new()
		stack.top_radius = 0.22
		stack.bottom_radius = 0.28
		stack.height = 0.9
		var stack_mi := MeshInstance3D.new()
		stack_mi.mesh = stack
		stack_mi.material_override = _make_material(train_data.body_color, 0.75)
		stack_mi.position = Vector3(0, 0.7, base_z - 0.4)
		nose.add_child(stack_mi)
		# 煙突から もくもく蒸気
		if train_data.has_steam:
			_attach_steam(nose, Vector3(0, 1.2, base_z - 0.4))
	return nose


# SL の煙突から立ちのぼる蒸気(白いふわふわ、上昇しながら拡大フェード)
func _attach_steam(parent: Node3D, pos: Vector3) -> void:
	var steam := GPUParticles3D.new()
	steam.amount = 14
	steam.lifetime = 2.2
	steam.preprocess = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	steam.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	steam.draw_pass_1 = qm
	steam.position = pos
	parent.add_child(steam)


func _attach_pantograph(car: Node3D) -> void:
	var roof_y: float = CAR_HEIGHT * 0.5 + 0.05
	# 台座
	var base := BoxMesh.new()
	base.size = Vector3(1.0, 0.06, 0.2)
	var base_mi := MeshInstance3D.new()
	base_mi.mesh = base
	base_mi.material_override = _make_material(WHEEL_COLOR, 0.5)
	base_mi.position = Vector3(0, roof_y + 0.03, 0)
	car.add_child(base_mi)

	# 「く」の字のアーム 2 本
	for x_off in [-0.18, 0.18]:
		var arm := CylinderMesh.new()
		arm.top_radius = 0.035
		arm.bottom_radius = 0.035
		arm.height = 0.75
		var arm_mi := MeshInstance3D.new()
		arm_mi.mesh = arm
		arm_mi.material_override = _make_material(WHEEL_COLOR, 0.5)
		arm_mi.position = Vector3(x_off, roof_y + 0.42, 0)
		arm_mi.rotate_x(0.35)
		car.add_child(arm_mi)

	# 集電板(上の横長 BoxMesh)
	var contact := BoxMesh.new()
	contact.size = Vector3(1.4, 0.04, 0.12)
	var contact_mi := MeshInstance3D.new()
	contact_mi.mesh = contact
	contact_mi.material_override = _make_material(WHEEL_COLOR, 0.5)
	contact_mi.position = Vector3(0, roof_y + 0.8, 0)
	car.add_child(contact_mi)


# === マテリアル生成 ===

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.1
	return mat


func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _make_emission_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
