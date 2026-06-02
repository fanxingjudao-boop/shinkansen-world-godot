extends Node3D

# 踏切(ふみきり)。1 つの踏切を自己完結で組み立て、電車の接近に反応して動く。
#
# 本格化のポイント:
# - 2 つの赤色警報灯が交互に点滅(踏切の象徴的な見た目)
# - 遮断機(しゃだんき)バーが、自ルートの電車が近づくと下りて、通り過ぎると上がる
#   (バーは黄色×黒の縞・ポールを軸に縦面で回転)
# - ×印の警標(漢字を使わない図形のみ)
# - やさしい警報音「カンカン」を、踏切が閉まっている間かつプレイヤーが近いときだけ
#   小さく鳴らす(怖くない・大きすぎない・刺激的でない)
#
# 設計方針(docs/ARCHITECTURE.md):
# - 見た目はスクリプト生成、判定ロジックは単純な距離(ワールド位置)で route の電車を見る。
# - 各 route(komachi / e235_yamanote)には専用の編成が 1 本ずつ。slug 一致でその編成を追う。
#   (本線3編成のワープ式分岐は komachi / yamanote を対象にしないため、編成は route から離れない)

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

# どの編成のルートの、どの位置(全長比)に置くか
@export var route_slug: String = ""
@export var route_ratio: float = 0.0
@export var railway_path: NodePath = NodePath("../Railway")
@export var trains_path: NodePath = NodePath("../Trains")
@export var player_path: NodePath = NodePath("../Player")

# 電車の中心がこの距離(m)以内に来たら遮断機を下ろす(接近=閉)。離れたら上げる。
const APPROACH_DIST: float = 22.0
# 警報音が聞こえる範囲(プレイヤーがこの距離以内のときだけ鳴らす。全踏切が常時鳴るのを防ぐ)
const RING_HEAR_DIST: float = 34.0
const BAR_SPEED: float = 2.6          # 遮断機の開閉スピード(rad/s 相当。ゆっくり優しく)
const OPEN_ANGLE: float = 1.35        # 開いた時のバーの角度(rad、約77°上向き)
const BLINK_HZ: float = 1.6           # 警報灯の点滅(交互)の速さ
const MIX_RATE: int = 22050

const POLE_C: Color = Color(0.28, 0.28, 0.31)
const RED_C: Color = Color(0.95, 0.25, 0.25)
const YELLOW_C: Color = Color(1.0, 0.82, 0.2)
const STRIPE_DARK: Color = Color(0.18, 0.18, 0.2)
const WHITE_C: Color = Color(0.96, 0.96, 0.96)
const ROAD_C: Color = Color(0.6, 0.6, 0.62)

var _railway: Node
var _trains: Node
var _player: Node3D
var _train: Node = null               # 自ルートの編成(slug 一致でキャッシュ)

var _bar_pivots: Array = []           # 遮断機の回転軸 [{ node: Node3D, sign: float }]
var _lights: Array = []               # 警報灯マテリアル [StandardMaterial3D, StandardMaterial3D]
var _closed_amount: float = 0.0       # 0=全開(バー上) .. 1=全閉(バー水平)
var _blink_t: float = 0.0
var _active: bool = false             # いま閉まろうとしている/閉まっているか
var _ring: AudioStreamPlayer
var _world_pos: Vector3 = Vector3.ZERO


# town.gd から、解決済みの railway / trains / player を注入する(NodePath の基準ずれ回避)。
# add_child(=_ready 実行)の前に呼ぶこと。
func set_sources(railway: Node, trains: Node, player: Node) -> void:
	_railway = railway
	_trains = trains
	_player = player as Node3D


func _ready() -> void:
	# ノードは town.gd から直接注入されることがある(その場合は再解決しない)。
	# 未注入なら NodePath から解決する(エディタ単体配置でも動くように)。
	if _railway == null:
		_railway = get_node_or_null(railway_path)
	if _trains == null:
		_trains = get_node_or_null(trains_path)
	if _player == null:
		_player = get_node_or_null(player_path) as Node3D
	if _railway == null or not _railway.has_method("get_route_sample"):
		push_warning("[Crossing] railway_path が未解決")
		return
	var s: Dictionary = _railway.get_route_sample(route_slug, route_ratio)
	if s.is_empty():
		push_warning("[Crossing] route_sample 取得失敗: %s@%.2f" % [route_slug, route_ratio])
		return
	var pos: Vector3 = s["position"]
	var fwd: Vector3 = s["forward"]
	var g: float = TerrainHeight.compute_height(pos.x, pos.z) + 0.32
	position = Vector3(pos.x, g, pos.z)
	_world_pos = position
	# ローカル -Z を線路方向へ(道はローカル X 方向に線路を横断)
	rotation.y = atan2(fwd.x, fwd.z)
	_build_visuals()
	_build_ring()


# === 毎フレーム: 接近判定 → 遮断機の開閉 → 警報灯の点滅 → 警報音 ===

func _process(delta: float) -> void:
	if _bar_pivots.is_empty():
		return
	_update_active()

	# 遮断機バーを目標へ滑らかに動かす(怖くない・急に動かない)
	var target: float = 1.0 if _active else 0.0
	_closed_amount = move_toward(_closed_amount, target, BAR_SPEED * delta * 0.6)
	for p in _bar_pivots:
		# 閉=水平(0) / 開=上向き(OPEN_ANGLE)。sign で左右の振り上げ向きを変える。
		var ang: float = (1.0 - _closed_amount) * OPEN_ANGLE * float(p["sign"])
		(p["node"] as Node3D).rotation.z = ang

	# 警報灯: 閉動作中だけ交互点滅。開いたら消灯。
	if _active:
		_blink_t += delta
		var on0: bool = sin(_blink_t * TAU * BLINK_HZ) >= 0.0
		_set_light(0, on0)
		_set_light(1, not on0)
	else:
		_set_light(0, false)
		_set_light(1, false)

	_update_ring()


# 自ルートの編成が APPROACH_DIST 以内にいるか(=遮断機を閉じるべきか)を判定。
func _update_active() -> void:
	if _train == null or not is_instance_valid(_train):
		_train = _find_route_train()
	if _train == null:
		_active = false
		return
	var tp: Vector3 = _train.get_ride_anchor_position()
	_active = _world_pos.distance_to(tp) < APPROACH_DIST


# slug 一致の編成を Trains から探す(1 ルート 1 編成)。
func _find_route_train() -> Node:
	if _trains == null:
		return null
	for t in _trains.get_children():
		if t.has_method("get_slug") and t.has_method("get_ride_anchor_position") \
				and String(t.get_slug()) == route_slug:
			return t
	return null


# === 警報音(やさしいカンカン。閉動作中かつプレイヤーが近いときだけ) ===

func _update_ring() -> void:
	if _ring == null:
		return
	var want: bool = _active and _player != null \
			and _world_pos.distance_to(_player.global_position) < RING_HEAR_DIST
	if want and not _ring.playing:
		_ring.play()
	elif not want and _ring.playing:
		_ring.stop()


# === 見た目の組み立て(Godot 操作層) ===

func _build_visuals() -> void:
	# 横断道路(線路を横切る板。ローカル X が道方向)
	_box(self, Vector3(9.0, 0.08, 3.6), Vector3(0, 0, 0), ROAD_C, 0.95)
	# 道の白線(両端に薄く)
	for sx in [-1.0, 1.0]:
		_box(self, Vector3(0.5, 0.02, 3.4), Vector3(sx * 3.6, 0.06, 0), WHITE_C, 0.9)

	# 両脇に警報機 + 遮断機
	for sx in [-1.0, 1.0]:
		_build_unit(sx)


# 片側の警報機(ポール・2 灯・×警標)+ 遮断機(回転軸 + 縞バー)を組む。
func _build_unit(sx: float) -> void:
	var base_x: float = sx * 3.7
	# ポール(濃灰、少し太め)
	_box(self, Vector3(0.26, 2.7, 0.26), Vector3(base_x, 1.35, 0), POLE_C, 0.6)
	# 上部の横板(警報灯の台座)
	_box(self, Vector3(1.1, 0.26, 0.3), Vector3(base_x, 2.78, 0), STRIPE_DARK, 0.5)

	# 警報灯 2 つ(交互点滅)。道(±X)を向く面に並べる。
	for i in range(2):
		var lx: float = base_x + (-0.28 if i == 0 else 0.28)
		var lamp := SphereMesh.new()
		lamp.radius = 0.17
		lamp.height = 0.34
		lamp.radial_segments = 10
		lamp.rings = 6
		var mi := MeshInstance3D.new()
		mi.mesh = lamp
		var mat := StandardMaterial3D.new()
		mat.albedo_color = RED_C
		mat.emission_enabled = true
		mat.emission = RED_C
		mat.emission_energy_multiplier = 0.0   # 初期は消灯
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		mi.position = Vector3(lx, 2.78, sx * 0.2)
		add_child(mi)
		_lights.append(mat)

	# ×印の警標(白い斜め十字 + 黄色ふち)。道を向く面(法線 ±X)に置く。
	_build_crossbuck(base_x, sx)

	# 遮断機: ポール上に回転軸(_bar_pivot)を置き、縞バーを内側(線路側)へ伸ばす。
	var pivot := Node3D.new()
	pivot.position = Vector3(base_x, 1.55, 0)
	add_child(pivot)
	_build_striped_bar(pivot, sx)
	_bar_pivots.append({ "node": pivot, "sign": sx })


# 黄色×黒の縞の遮断機バー。pivot から内側(-sx 方向)へ伸ばす。
func _build_striped_bar(pivot: Node3D, sx: float) -> void:
	var bar_len: float = 3.0
	var seg: int = 6
	var seg_len: float = bar_len / float(seg)
	for i in range(seg):
		var c: Color = YELLOW_C if i % 2 == 0 else STRIPE_DARK
		# pivot から内側へ。中心が -sx*( (i+0.5)*seg_len ) に来るよう配置。
		var cx: float = -sx * (seg_len * 0.5 + i * seg_len)
		_box(pivot, Vector3(seg_len, 0.16, 0.16), Vector3(cx, 0, 0), c, 0.6)
	# 先端の赤い丸(止まれの目印)
	_mesh(pivot, _sphere(0.12), Vector3(-sx * bar_len, 0, 0), RED_C, 0.5)


# ×印の警標を base_x のポール上部、道を向く面に作る。
func _build_crossbuck(base_x: float, sx: float) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(base_x + sx * 0.16, 3.25, 0)
	# 道(±X)を向くように、板を Y-Z 面へ(法線 ±X)。斜めの 2 本で × を作る。
	add_child(holder)
	for rot in [0.9, -0.9]:   # 約 ±51°
		var arm := BoxMesh.new()
		arm.size = Vector3(0.05, 0.95, 0.12)
		var mi := MeshInstance3D.new()
		mi.mesh = arm
		mi.material_override = _mat(WHITE_C, 0.5)
		mi.rotation.x = rot     # X 軸まわりに傾けて Y-Z 面で交差(法線は X 方向)
		holder.add_child(mi)
	# 黄色いふち(背板)
	var back := BoxMesh.new()
	back.size = Vector3(0.04, 1.0, 1.0)
	var bmi := MeshInstance3D.new()
	bmi.mesh = back
	bmi.material_override = _mat(YELLOW_C, 0.6)
	bmi.position = Vector3(-sx * 0.04, 0, 0)
	bmi.rotation.z = PI * 0.25  # ひし形に見せる
	holder.add_child(bmi)


# === 警報音(PCM 生成・ループ) ===

# やさしい「カンカン」のループ音を作る。2 つの柔らかいトーンを少し間を空けて鳴らし、
# 角を丸めた包絡線で刺激を抑える。音量は控えめ。
func _build_ring() -> void:
	_ring = AudioStreamPlayer.new()
	_ring.volume_db = -16.0   # 控えめ(怖くない・うるさくない)
	add_child(_ring)
	_ring.stream = _make_ring_loop()


func _make_ring_loop() -> AudioStreamWAV:
	var dur: float = 0.5             # 1 ループ = 0.5 秒(カン…カン…)
	var n: int = int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	# 2 つの打点(0.0〜 と 0.25〜)。それぞれ短い減衰でやわらかく。
	for i in range(n):
		var t: float = float(i) / float(MIX_RATE)
		var s: float = 0.0
		s += _ping(t, 0.0, 1175.0)    # 1 打目(D6 付近・明るいが柔らかい)
		s += _ping(t, 0.25, 988.0)    # 2 打目(B5・少し低い)
		var v: int = int(clamp(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	wav.data = data
	return wav


# 1 打分の柔らかいトーン(start 秒から立ち上がり、すばやく減衰)。
func _ping(t: float, start: float, freq: float) -> float:
	var dt: float = t - start
	if dt < 0.0 or dt > 0.22:
		return 0.0
	var env: float = exp(-dt * 16.0) * sin(min(dt * 40.0, PI))  # 立ち上がり丸め+減衰
	return sin(TAU * freq * dt) * env * 0.4


# === メッシュ/マテリアルヘルパー ===

func _set_light(idx: int, on: bool) -> void:
	if idx < 0 or idx >= _lights.size():
		return
	(_lights[idx] as StandardMaterial3D).emission_energy_multiplier = 2.2 if on else 0.0


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.05
	return m


func _box(root: Node3D, size: Vector3, pos: Vector3, color: Color, rough: float) -> void:
	var b := BoxMesh.new()
	b.size = size
	_mesh(root, b, pos, color, rough)


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 5
	return s


func _mesh(root: Node3D, mesh: Mesh, pos: Vector3, color: Color, rough: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, rough)
	mi.position = pos
	root.add_child(mi)
