extends Node3D

# class_name は Godot エディタが project をスキャンするまで CLI で
# 認識されないため preload 両対応
const TrainData = preload("res://scripts/entities/train_data.gd")
const FONT_BODY = preload("res://assets/fonts/MPLUSRounded1c-Medium.ttf")  # ♥ エフェクト用

# 列車本体スクリプト。
# - _ready で railway の Path3D を取得し、PathFollow3D を動的に add_child
# - _physics_process で「弧長(実距離)」progress を等速で進める(固定 60Hz)。
#   ※ 旧実装は progress_ratio = 角度t/TAU だったが、楕円+高低差で
#     「角度あたりの実距離」が変動するため坂で急加速/急減速していた。
#     弧長ベースにして線路上を常に一定速度で走るようにした(滑らか)。
# - 見た目は train_data に応じてスクリプトで全部組み立て(5 両編成、個別窓、台車、連結部)

@export var train_data: TrainData
@export var railway_path: NodePath

# 駅(dwell)に到着した瞬間に発火。引数は編成中央のワールド位置。
# StationManager が受けて、その駅のテーマ短メロ(駅メロ)を鳴らす。
signal arrived(anchor_pos: Vector3)
# 駅から発車した瞬間(DWELLING→RUNNING)に発火。乗車中アナウンス「しゅっぱつ」用。
signal departed()

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
# 車輪を回すのはカメラからこの距離(m)以内の編成だけ(遠くの編成は静止でも気づかれない)。
# 9 編成 × 40 輪を毎フレーム回すと塵も積もるため、近接ゲートで負荷を抑える。
const WHEEL_ANIM_RANGE: float = 110.0

const WINDOW_COLOR: Color = Color(0.4, 0.8, 1.0)       # #66ccff
const WHEEL_COLOR: Color = Color(0.13, 0.13, 0.13)
const BOGIE_COLOR: Color = Color(0.25, 0.25, 0.28)     # 台車の濃灰
const COUPLER_COLOR: Color = Color(0.18, 0.18, 0.20)   # 連結部の暗灰
const HEADLIGHT_COLOR: Color = Color(1.0, 1.0, 0.8)

# === 乗客(A-5 遊び心: 窓から手を振る)===
# 窓の内側に乗客シルエットを置く。大半は静止(車両ごと MultiMesh=1 draw call・距離カリング)で
# 「乗っている」感を出し、各車両に 1 人だけ「挨拶する乗客」を実ノードで作って、
# すれ違いざまに ぴょこっと喜ぶ(上下バウンス+♥)。腕は出さない(細い棒が動くと幼児には怖い)。
# 怖くないよう顔は作らず真っ黒も使わない。
const PASSENGER_INSET: float = 0.06        # 窓より内側へ引っ込める量(X)
const PASSENGER_Y: float = 0.06            # 窓中心(0.18)よりやや下=座っている高さ
const PASSENGER_RADIUS: float = 0.16       # シルエットの頭+肩の大きさ
const WAVE_COOLDOWN: float = 3.5           # 手振りの最短間隔(連発防止)
# やわらかい乗客カラー(真っ黒にしない=不気味さ回避)。編成ごとに開始位置を変えて彩りを出す。
const PASSENGER_COLORS: Array = [
	Color(0.96, 0.78, 0.62),  # はだ色
	Color(0.62, 0.74, 0.95),  # みずいろ
	Color(0.98, 0.74, 0.82),  # ももいろ
	Color(0.78, 0.90, 0.66),  # わかくさ
	Color(1.0, 0.86, 0.55),   # きいろ
]

# 停車: 停車点(dwell/park)の手前で減速し、点を跨いだら停止する。
const STOP_SLOW_RANGE_M: float = 26.0    # 停車点の手前この距離(m)で減速
const STOP_MIN_FACTOR: float = 0.18      # 停車点直前の速度係数

# 走行状態。RUNNING=走行 / DWELLING=数秒停車中 / PARKED=車庫で待機(発車待ち)
enum State { RUNNING, DWELLING, PARKED }

var _path_follow: PathFollow3D     # 編成中央(乗車カメラ/アンカー用。見た目は持たない)
var _parts: Array = []             # 各車両・連結部 {follow: PathFollow3D, offset: float(弧長)}
var _wheels: Array = []            # 全車輪の MeshInstance3D(走行に応じて回す。近接時のみ)
var _passenger_mmis: Array = []    # 静止乗客の MultiMeshInstance3D(距離カリング対象)
var _wavers: Array = []            # 挨拶でぴょこっと喜ぶ乗客 [{root: Node3D, base_y: float}]
var _passengers_visible: bool = true
var _passengers_waving: bool = false
var _wave_cooldown: float = 0.0
var _color_seed: int = 0           # 乗客色のローテーション開始(編成ごとに変える)
var _progress: float = 0.0          # 線路上の現在位置(弧長, メートル)
var _length: float = 0.0            # 線路一周の弧長
var _linear_speed: float = 0.0      # 実速度(m/s)。旧角速度から周回時間を保つよう換算
var _stops: Array = []             # [{ offset, kind, seconds }] 自ルートの停車点
var _state: int = State.RUNNING
var _dwell_timer: float = 0.0
var _spin_advance: float = 0.0     # 直近フレームの前進量(m)。車輪回転に使う
var _just_arrived: bool = false    # このフレームに駅へ着いたか(到着後に arrived を発火)
var _panto: Array = []             # パンタグラフの可動パーツ [{node, base_y}]
var _panto_phase: float = 0.0      # パンタグラフ上下動の位相

# === うんてんしゅモード(運転手スロットル) ===
# 乗車中に「うんてん」を選ぶと _driver_mode=true。RUNNING の前進量に _driver_throttle を
# 乗算して「ゴー/とまれ」を実現する。非運転時は乗算係数を 1.0 に固定するので自動走行は不変。
# _driver_throttle は _driver_target へ THROTTLE_EASE 速度で ease(急発進・急停止しない=バネ感)。
const THROTTLE_EASE: float = 1.8     # スロットル追従速度(1秒あたり)。小さいほどゆっくり加減速
const DRIVER_STOP_EPS: float = 0.02  # これ未満は実質停止扱い(添え演出「ぴったり とうちゃく」判定に使う)
var _driver_mode: bool = false       # 運転手モードか(opt-in)
var _driver_throttle: float = 0.0    # 現在のスロットル係数 0..1(実際に advance へ乗算)
var _driver_target: float = 0.0      # 目標スロットル(ゴー=1.0 / とまれ=0.0)

# いま実際に走っているルートの slug。初期は train_data.slug だが、分岐ワープ(switch_route)
# で別ルートへ載り替えると更新される。get_slug()(編成の識別子=図鑑用)とは別物。
# 分岐検出はこの「実トラックの slug」で行う(でないと載り替え後に別ルートの分岐点を見てしまう)。
var _active_slug: String = ""


var _inited: bool = false       # 初期化(ルート取得+車両組み立て)完了フラグ
var _dead: bool = false         # 設定ミスなど回復不能 → 再試行しない
var _init_tries: int = 0


func _ready() -> void:
	# 初期化は _try_init() に集約。Railway のルート生成や Curve3D のベイクが
	# まだ間に合っていない(ノード順・書き出し環境のタイミング差)場合でも、
	# ここで諦めず _process で準備できるまで毎フレーム再試行する。
	# ※ 旧実装は _ready 一発で失敗すると永久に動かなかった(Web で電車が止まる一因の疑い)。
	_try_init()


# 初期化を試みる。成功したら _inited=true。準備未完なら false を返し後で再試行。
func _try_init() -> bool:
	if train_data == null:
		_fail("train_data が未設定")
		return false
	if railway_path.is_empty():
		_fail("railway_path が未設定")
		return false
	var railway := get_node_or_null(railway_path)
	if railway == null or not railway.has_method("get_route_path"):
		return false  # Railway がまだ _ready していない可能性 → 次フレーム再試行
	var path_node: Path3D = railway.get_route_path(train_data.slug)
	if path_node == null or path_node.curve == null:
		return false  # ルート未生成 → 再試行

	# 弧長ベースの移動を準備。書き出し環境で長さ 0 が返る事故に備え、
	# まずベイクを明示的に促してから長さを取得し、0 なら準備未完として再試行する。
	var curve := path_node.curve
	curve.get_baked_points()
	_length = curve.get_baked_length()
	if _length <= 0.0:
		return false
	# 一周 = TAU/speed 秒(編成ごとの速度感を維持。ルート長が違っても周回時間は speed 基準)。
	_linear_speed = train_data.speed * _length / TAU
	_progress = railway.get_route_start_offset(train_data.slug)
	_stops = railway.get_route_stops(train_data.slug)
	_active_slug = train_data.slug  # 起動時は自分の専用ルート上にいる
	_color_seed = absi(hash(train_data.slug))  # 乗客の色を編成ごとに変える
	if not _stops.is_empty() and String(_stops[0]["kind"]) == "park":
		# park 編成は最初から車庫位置で停止しておく
		_progress = float(_stops[0]["offset"])
		_state = State.PARKED

	# 中央 PathFollow(乗車カメラ/アンカー)+ 各車両・連結部を個別の PathFollow に載せる。
	# 編成を弧長方向にずらして配置することで、坂やカーブで各車両が自分の位置の
	# 線路に沿って屈折し、先頭車が宙に浮かない(剛体1点追従だと浮いていた)。
	_path_follow = _make_follow(path_node)
	_build_cars(path_node)
	_apply_progress()
	_inited = true
	return true


func _fail(reason: String) -> void:
	if not _dead:
		_dead = true
		push_warning("[Train] %s" % reason)


# 物理フレーム(固定 60Hz)で走らせる。_process(描画レート)だと iPad など描画 fps が
# 低い端末で電車だけ進まず「止まって見える」(プレイヤーは _physics_process なので滑らか)。
# 物理プロセスなら描画が重くてもキャッチアップで時間どおり進む(delta も一定なので
# 巨大 delta による停車点スキップも起きず、クランプ不要)。
func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not _inited:
		_init_tries += 1
		if not _try_init():
			if _init_tries == 120:
				push_warning("[Train] 初期化が未完のまま(ルート未取得): %s" % (train_data.slug if train_data else "?"))
			return
	if _wave_cooldown > 0.0:
		_wave_cooldown -= delta
	# 運転手モード中のみスロットルを目標へ ease(非運転時は触らない=自動走行不変)。
	if _driver_mode:
		_driver_throttle = move_toward(_driver_throttle, _driver_target, THROTTLE_EASE * delta)
	_spin_advance = 0.0
	match _state:
		State.RUNNING:
			var factor: float = _slow_factor_at(_progress)
			# 運転中は手動スロットル、非運転は 1.0(恒等)を掛ける。
			var throttle: float = _driver_throttle if _driver_mode else 1.0
			var advance: float = _linear_speed * factor * throttle * delta
			_spin_advance = advance
			var prev: float = _progress
			_progress = fposmod(prev + advance, _length)
			var hit = _crossed_stop(prev, advance)
			if hit != null:
				_progress = fposmod(float(hit["offset"]), _length)
				if String(hit["kind"]) == "park":
					_state = State.PARKED
				else:
					_state = State.DWELLING
					_dwell_timer = float(hit["seconds"])
					_just_arrived = true  # 位置確定後(_apply_progress 後)に arrived を発火
		State.DWELLING:
			_dwell_timer -= delta
			if _dwell_timer <= 0.0:
				_state = State.RUNNING
				departed.emit()
		State.PARKED:
			pass
	_apply_progress()
	_spin_wheels()
	_update_passenger_cull()
	if _just_arrived:
		_just_arrived = false
		arrived.emit(_path_follow.global_position)  # 位置確定後に発火(駅メロ用)


# 走行に応じて車輪を回す。近くの編成だけ(遠方は静止でも気づかれない=負荷削減)。
# 車輪は _build_wheel で rotate_z(90°) 済み = ローカル Y 軸が車軸(左右)。
# その軸まわりに回せば転がって見える。回す角度 = 進んだ距離 / 半径。
func _spin_wheels() -> void:
	if _spin_advance <= 0.0 or _wheels.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _path_follow.global_position.distance_to(cam.global_position) > WHEEL_ANIM_RANGE:
		return
	var angle: float = _spin_advance / WHEEL_RADIUS
	for w in _wheels:
		(w as Node3D).rotate_object_local(Vector3.UP, angle)


# パンタグラフをゆっくり上下に微動させて生命感を出す(架線に追従する雰囲気)。
# 走行中は少し高め、停車中はわずかに下がる。視覚のみで負荷は軽微。
func _process(delta: float) -> void:
	if _panto.is_empty():
		return
	_panto_phase += delta
	var raised: float = 0.0 if _state == State.RUNNING else -0.04
	var bob: float = sin(_panto_phase * 1.6) * 0.03 + raised
	for p in _panto:
		(p["node"] as Node3D).position.y = float(p["base_y"]) + bob


# このフレームの前進(prev から advance メートル)で跨いだ停車点を返す(なければ null)。
# 直前に発車した点を即再ヒットしないよう d_to は厳密に正のものだけ採用。
func _crossed_stop(prev: float, advance: float):
	if advance <= 0.0:
		return null
	var best = null
	var best_d: float = advance + 1.0
	for s in _stops:
		var d_to: float = fposmod(float(s["offset"]) - prev, _length)
		if d_to > 0.0001 and d_to <= advance and d_to < best_d:
			best = s
			best_d = d_to
	return best


# 将来プレイヤーが車庫の編成を発車させる(park 解除)
func depart() -> void:
	if _state == State.PARKED:
		_state = State.RUNNING


# 中央 + 各パートの PathFollow を現在の弧長位置に反映
func _apply_progress() -> void:
	_path_follow.progress = _progress
	for p in _parts:
		(p["follow"] as PathFollow3D).progress = fposmod(_progress + p["offset"], _length)


# 線路に沿う PathFollow3D を 1 つ生成して path_node に追加
func _make_follow(path_node: Path3D) -> PathFollow3D:
	var f := PathFollow3D.new()
	f.loop = true
	f.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_node.add_child(f)
	return f


# === ロジック層 ===

# 停車点に近いほど速度係数を STOP_MIN_FACTOR まで落とす(急停止を避けバネ感のある減速)。
# 複数点が近い場合は最も遅い係数を採用。距離は周回のラップを考慮。
func _slow_factor_at(progress: float) -> float:
	var factor: float = 1.0
	for s in _stops:
		var d: float = absf(_wrap_dist(progress, float(s["offset"])))
		if d < STOP_SLOW_RANGE_M:
			factor = minf(factor, lerpf(STOP_MIN_FACTOR, 1.0, d / STOP_SLOW_RANGE_M))
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

# 先頭車の PathFollow(前面展望カメラ用)。_parts[0] は lead 車(_build_cars で最初に追加)。
func get_ride_mount_front() -> Node3D:
	if _parts.is_empty():
		return _path_follow
	return _parts[0]["follow"]

# 編成中央の現在の進行方向(ワールド)。-Z が進行方向(先頭)。
func get_ride_forward() -> Vector3:
	if _path_follow == null:
		return -global_transform.basis.z
	return -_path_follow.global_transform.basis.z

# 表示名(ひらがな)。プロンプト・通知用。
func get_display_name() -> String:
	return train_data.display_name if train_data else ""

# 内部識別子(図鑑の発見記録用)。編成の「正体」。分岐ワープしても変わらない。
func get_slug() -> String:
	return train_data.slug if train_data else ""

# いま実際に走っているルートの slug(分岐ワープで変わる)。分岐検出・ルート入れ替えに使う。
func get_route_slug() -> String:
	return _active_slug if _active_slug != "" else get_slug()


# === うんてんしゅモード public API(RideController から呼ばれる) ===

# 運転手モードに入る。突入の段差をなくすため、入った瞬間は今までどおり走り続ける
# (throttle=1.0)。止まらない=こわくない。以降「ゴー/とまれ」で _driver_target を操作。
func enter_driver_mode() -> void:
	_driver_mode = true
	_driver_target = 1.0
	_driver_throttle = 1.0


# 運転手モードを抜けて自動走行へ滑らかに復帰(常用速度に戻す)。
func exit_driver_mode() -> void:
	_driver_mode = false
	_driver_target = 1.0
	_driver_throttle = 1.0


# 目標スロットルを設定(ゴー=1.0 / とまれ=0.0)。実際の速度は ease で滑らかに追従。
func set_driver_throttle(target: float) -> void:
	_driver_target = clampf(target, 0.0, 1.0)


# 運転中で、ほぼ止まっているか(添え演出「ぴったり とうちゃく」の判定用)。
func is_driver_stopped() -> bool:
	return _driver_mode and _driver_throttle < DRIVER_STOP_EPS


# 線路一周に対する現在位置の比(0..1)。分岐接近判定に使う。
func get_progress_ratio() -> float:
	if _length <= 0.0:
		return 0.0
	return fposmod(_progress, _length) / _length


# === ワープ式分岐: 走行中の編成を別ルートの Path3D へ載せ替える ===
# 物理的な分岐レールは作らず、全 PathFollow3D を新しい Path3D に reparent して
# 弧長系(_length/_stops/_linear_speed/_progress)を差し替える。
# 呼び出し側(RideController)は必ずフェードの中点(画面が隠れている間)で呼ぶこと。
# reparent 直後に古い progress のまま描画されると位置が飛ぶため、ここで即 _apply_progress() する。
func switch_route(new_slug: String, new_path: Path3D, new_progress: float, new_length: float,
		new_stops: Array, new_linear_speed: float) -> void:
	if new_path == null or new_path.curve == null or new_length <= 0.0:
		return
	_reparent_follow(_path_follow, new_path)
	for p in _parts:
		_reparent_follow(p["follow"] as PathFollow3D, new_path)
	_active_slug = new_slug       # 実トラックの slug を更新(分岐検出が正しく動く)
	_length = new_length
	_stops = new_stops
	_linear_speed = new_linear_speed
	_progress = fposmod(new_progress, _length)
	_state = State.RUNNING       # 念のため(DWELLING 跨ぎ事故防止)
	_dwell_timer = 0.0
	_apply_progress()            # 即座に新位置へスナップ(フェード中なので不可視)


# PathFollow3D を現在の親 Path3D から外して new_path の子にする。
# loop / rotation_mode はノード自身が保持するので再設定不要(progress は switch_route で代入)。
func _reparent_follow(f: PathFollow3D, new_path: Path3D) -> void:
	if f == null:
		return
	var parent := f.get_parent()
	if parent:
		parent.remove_child(f)
	new_path.add_child(f)


# === メッシュ構築(Godot 操作層) ===

# 各車両・連結部をそれぞれ独立した PathFollow3D に載せ、編成中心からの
# 弧長オフセットを記録する。offset は「中心より進行方向側(先頭)なら正」。
# PathFollow ローカル -Z が進行方向 = progress 増加方向なので、ローカル Z=cz の
# パートのオフセットは -cz(先頭 cz<0 → offset>0 → 中心より前 = progress 大)。
func _build_cars(path_node: Path3D) -> void:
	var lengths: Array = [LEAD_LENGTH, MID_LENGTH, MID_LENGTH, MID_LENGTH, LEAD_LENGTH]
	var roles: Array = ["lead", "mid", "mid", "mid", "tail"]

	var total_length: float = 0.0
	for l in lengths:
		total_length += l
	total_length += COUPLER_LENGTH * (CAR_COUNT - 1)

	var cursor_z: float = -total_length * 0.5  # 一番手前(進行方向側)から開始
	for i in range(CAR_COUNT):
		var car_len: float = lengths[i]
		var role: String = roles[i]
		var car_center_z: float = cursor_z + car_len * 0.5
		var car := _build_car(car_len, role)
		car.position = Vector3(0, CAR_BASE_Y, 0)  # 沿線方向は PathFollow が担当
		if role == "tail":
			car.rotate_y(PI)  # 末尾車は逆向き(後部運転台)
		var f := _make_follow(path_node)
		f.add_child(car)
		_parts.append({ "follow": f, "offset": -car_center_z })
		cursor_z += car_len

		# 次の車両との間に連結部
		if i < CAR_COUNT - 1:
			var coupler_center_z: float = cursor_z + COUPLER_LENGTH * 0.5
			var coupler := _build_coupler()
			coupler.position = Vector3(0, CAR_BASE_Y - 0.15, 0)
			var cf := _make_follow(path_node)
			cf.add_child(coupler)
			_parts.append({ "follow": cf, "offset": -coupler_center_z })
			cursor_z += COUPLER_LENGTH


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

	# 窓の内側に乗客(A-5)。窓と同じ座標式で配置する。
	_attach_passengers(car, car_len, window_count, role)

	# 台車(各車両 2 台、前後)
	_attach_bogie(car, car_len, +1.0)
	_attach_bogie(car, car_len, -1.0)

	# 役割別パーツ
	if role == "lead" or role == "tail":
		_attach_nose_and_headlight(car, car_len)
	elif role == "mid" and train_data.has_pantograph:
		_attach_pantograph(car)

	return car


# 窓は数が多く(編成全体で数百個)、同一メッシュ・同一マテリアル・静止なので
# 車両ごとに MultiMesh で 1 draw call に集約する(性能対策・見た目は不変)。
func _attach_windows(car: Node3D, car_len: float, count: int) -> void:
	var window_zone: float = car_len - 1.4  # 両端を残して窓を配置する範囲
	var window_width: float = (window_zone - WINDOW_GAP * (count - 1)) / float(count)
	var start_z: float = -window_zone * 0.5

	var w := BoxMesh.new()
	w.size = Vector3(0.04, WINDOW_HEIGHT, window_width)
	w.material = _make_unshaded_material(WINDOW_COLOR)  # 共有マテリアル

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = w
	mm.instance_count = count * 2
	var idx: int = 0
	for i in range(count):
		var center_z: float = start_z + window_width * 0.5 + i * (window_width + WINDOW_GAP)
		for side in [1.0, -1.0]:
			var origin := Vector3(side * (CAR_WIDTH * 0.5 + 0.01), 0.18, center_z)
			mm.set_instance_transform(idx, Transform3D(Basis(), origin))
			idx += 1

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	car.add_child(mmi)


# 乗客(A-5)。窓と同じ座標式で、窓の内側に乗客シルエットを置く。
# 大半は静止(車両ごと MultiMesh=1 draw call・遠景は距離カリングで非表示)、
# 各車両に 1 人だけ「手を振る乗客」を実ノードで作る(_wavers に保持)。
func _attach_passengers(car: Node3D, car_len: float, count: int, role: String) -> void:
	var window_zone: float = car_len - 1.4
	var window_width: float = (window_zone - WINDOW_GAP * (count - 1)) / float(count)
	var start_z: float = -window_zone * 0.5
	var inset_x: float = CAR_WIDTH * 0.5 - PASSENGER_INSET
	var sit_color: Color = PASSENGER_COLORS[_color_seed % PASSENGER_COLORS.size()]

	# --- 静止乗客: 1つおきの窓×両側に丸いシルエット(MultiMesh)---
	var seats: Array = []
	for i in range(count):
		if i % 2 == 1:
			continue  # 1つおき(自然なまばら感。奇数窓は手振り乗客用に空ける)
		var cz: float = start_z + window_width * 0.5 + i * (window_width + WINDOW_GAP)
		for side in [1.0, -1.0]:
			seats.append(Vector3(side * inset_x, PASSENGER_Y, cz))
	if seats.size() > 0:
		var head := SphereMesh.new()
		head.radius = PASSENGER_RADIUS
		head.height = PASSENGER_RADIUS * 2.0
		head.radial_segments = 8
		head.rings = 4
		head.material = _make_unshaded_material(sit_color.darkened(0.08))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = head
		mm.instance_count = seats.size()
		for s in range(seats.size()):
			mm.set_instance_transform(s, Transform3D(Basis(), seats[s]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		car.add_child(mmi)
		_passenger_mmis.append(mmi)

	# --- 手を振る乗客: 奇数窓のひとつ(static が空けた席)に 1 人 ---
	if count >= 2:
		var wi: int = 1
		var wcz: float = start_z + window_width * 0.5 + wi * (window_width + WINDOW_GAP)
		# 車両ごとに左右を交互にして、両側に乗客が見えるようにする。
		var wside: float = 1.0 if (_color_seed + (1 if role == "tail" else 0)) % 2 == 0 else -1.0
		_build_waver(car, Vector3(wside * inset_x, PASSENGER_Y, wcz), sit_color)


# すれ違いざまに「ぴょこっ」と喜ぶ乗客 1 人を組み立てる。胴体+頭(やわらかい色・顔なし)のみ。
# 腕は出さない(細い棒が動くと幼児には怖い=改善さんフィードバック v0.51.1)。挨拶は上下バウンスで表す。
func _build_waver(car: Node3D, window_pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.position = window_pos

	var body := MeshInstance3D.new()
	var bmesh := SphereMesh.new()
	bmesh.radius = PASSENGER_RADIUS
	bmesh.height = PASSENGER_RADIUS * 2.2
	bmesh.radial_segments = 8
	bmesh.rings = 4
	body.mesh = bmesh
	body.material_override = _make_unshaded_material(color)
	root.add_child(body)

	car.add_child(root)
	_wavers.append({ "root": root, "base_y": window_pos.y })


# すれ違いざまに乗客が手を振る(TrainGreeters から呼ばれる public API)。
# 連発はクールダウンで防ぎ、遠い編成(振っても見えない)は処理しない。
func wave_passengers() -> void:
	if _passengers_waving or _wave_cooldown > 0.0 or _wavers.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null and _path_follow != null \
			and _path_follow.global_position.distance_to(cam.global_position) > WHEEL_ANIM_RANGE:
		return
	_passengers_waving = true
	_wave_cooldown = WAVE_COOLDOWN
	for w in _wavers:
		var root := w["root"] as Node3D
		if root == null:
			continue
		var base_y: float = float(w["base_y"])
		var tw := create_tween()
		# ぴょこっと 喜ぶ(animal.wave_back と同じやさしいバウンス。腕は出さない=怖くない)
		tw.tween_property(root, "position:y", base_y + 0.18, 0.16) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(root, "position:y", base_y, 0.28) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_pop_wave_heart()
	var done := create_tween()
	done.tween_interval(0.5)
	done.tween_callback(func() -> void: _passengers_waving = false)


# 手振り乗客の窓から ♥ をひとつ ふわっと(温かさ。animal._pop_heart 流用)。
func _pop_wave_heart() -> void:
	if _wavers.is_empty():
		return
	var anchor := _wavers[0]["root"] as Node3D
	if anchor == null:
		return
	var heart := Label3D.new()
	heart.text = "♥"
	heart.font = FONT_BODY
	heart.font_size = 80
	heart.pixel_size = 0.006
	heart.modulate = Color(1.0, 0.5, 0.65)
	heart.outline_size = 10
	heart.outline_modulate = Color(1, 1, 1, 1)
	heart.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	heart.position = Vector3(0, 0.5, 0)
	anchor.add_child(heart)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(heart, "position:y", 1.2, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(heart, "modulate:a", 0.0, 0.9)
	tw.chain().tween_callback(heart.queue_free)


# 静止乗客 MultiMesh の距離カリング(遠景では非表示=負荷ゼロ)。車輪と同じ近接基準。
func _update_passenger_cull() -> void:
	if _passenger_mmis.is_empty() or _path_follow == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var near: bool = _path_follow.global_position.distance_to(cam.global_position) <= WHEEL_ANIM_RANGE
	if near == _passengers_visible:
		return
	_passengers_visible = near
	for m in _passenger_mmis:
		(m as Node3D).visible = near


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
			_wheels.append(wheel)  # 走行に応じた回転のため参照を保持


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
		_panto.append({ "node": arm_mi, "base_y": arm_mi.position.y })

	# 集電板(上の横長 BoxMesh)
	var contact := BoxMesh.new()
	contact.size = Vector3(1.4, 0.04, 0.12)
	var contact_mi := MeshInstance3D.new()
	contact_mi.mesh = contact
	contact_mi.material_override = _make_material(WHEEL_COLOR, 0.5)
	contact_mi.position = Vector3(0, roof_y + 0.8, 0)
	car.add_child(contact_mi)
	_panto.append({ "node": contact_mi, "base_y": contact_mi.position.y })


# === マテリアル生成(色キーで共有・性能対策) ===
# 旧実装は呼ぶたびに新しい StandardMaterial3D を作っていた(窓・車輪・台車など色が
# 定数のパーツでも 1000 個超のマテリアルが生成されていた)。色+粗さ+種別をキーに
# 共有キャッシュ化して、VRAM とレンダラーの状態切替を大幅に削減する。見た目は不変。
# static なので全編成・全シーンで 1 つのキャッシュを共有(定数色は全部 1 個に集約)。
static var _mat_cache: Dictionary = {}


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var key: String = "s|%s|%.2f" % [color.to_html(true), roughness]
	var cached = _mat_cache.get(key)
	if cached:
		return cached
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.1
	_mat_cache[key] = mat
	return mat


func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	var key: String = "u|%s" % color.to_html(true)
	var cached = _mat_cache.get(key)
	if cached:
		return cached
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = mat
	return mat


func _make_emission_material(color: Color) -> StandardMaterial3D:
	var key: String = "e|%s" % color.to_html(true)
	var cached = _mat_cache.get(key)
	if cached:
		return cached
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = mat
	return mat
