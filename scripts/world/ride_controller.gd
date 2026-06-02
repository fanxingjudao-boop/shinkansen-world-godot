extends Node3D

# 乗車システムの中核。歩行中 / 乗車中の状態を管理し、
# interact(タッチ / E / Enter)のトグルで乗降を制御する。
#
# 設計方針(docs/ARCHITECTURE.md):
# - Autoload を使わず Main 直下のノードに状態を集約。
#   Train / Player / Camera / HUD は「操作される側」に徹する。
# - interact は touch_hud.gd が action_press するのみで誰も消費していない。
#   このノードが唯一の is_action_just_pressed("interact") 消費者になる。
# - 乗車カメラは電車の PathFollow3D(ROTATION_ORIENTED, -Z が進行方向)の子に
#   ローカル固定 transform で置くので、進行方向に追従しつつ一切揺れない。
# - カメラ切替の瞬間はやさしいフェードで隠す(怖くない・酔わない)。
# - 判定ロジックは static な純粋関数に分離(C# 移植配慮)。

# class_name は CLI スキャン前に認識されないため preload で型解決(train_data.gd と同方針)
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")
const Train = preload("res://scripts/entities/train.gd")
const TouchHud = preload("res://scripts/ui/touch_hud.gd")
const RouteData = preload("res://scripts/world/route_data.gd")

enum State { WALKING, RIDING }

const RIDE_RANGE: float = 14.0          # この距離内の電車に乗れる(編成全長 ~26m の半分強)
const TOGGLE_DEBOUNCE: float = 0.4      # 乗降トグルのクールダウン(乗った直後の即降車防止)
const FADE_TIME: float = 0.25           # フェード片道の秒数
const LANDING_OFFSET: float = 6.0       # 降車時に線路中心から外側へずらす距離(電車・レールに重ならない)
const PLAYER_GROUND_OFFSET: float = 1.5 # 降車時の地形からの足元オフセット(main.gd と同値)

# 乗車カメラのプリセット(やね / うんてんせき / まどぎわ)。HUD の「ながめ」ボタンで巡回。
# mount: "center"=編成中央 / "front"=先頭車。pos/pitch/yaw はそのマウント子のローカル値。
# PathFollow3D は ROTATION_ORIENTED で -Z が進行方向なので、固定 transform で揺れず追従する。
const RIDE_VIEWS: Array = [
	{ "name": "やね", "mount": "center", "pos": Vector3(0.0, 6.0, 6.0), "pitch": -28.0, "yaw": 0.0, "fov": 60.0 },
	{ "name": "うんてんせき", "mount": "front", "pos": Vector3(0.0, 2.5, 2.6), "pitch": -7.0, "yaw": 0.0, "fov": 70.0 },
	{ "name": "まどぎわ", "mount": "center", "pos": Vector3(4.8, 2.4, 0.6), "pitch": -8.0, "yaw": 52.0, "fov": 62.0 },
]

# 車内アナウンス用
const MIX_RATE: int = 22050
const ANNOUNCE_NEAR_STATION: float = 26.0  # 到着位置からこの距離以内の駅名をアナウンス

# うんてんしゅモードの分岐(ワープ)用
const BRANCH_PREVIEW_RATIO: float = 0.05   # 分岐点の何割手前で2択を出すか(ルート長基準)
const BRANCH_PASS_RATIO: float = 0.01      # 分岐点をこれだけ過ぎたら直進確定で消す
const PERFECT_STOP_TONE_A: float = 660.0   # 「ぴったり とうちゃく」ごほうび音(上昇)
const PERFECT_STOP_TONE_B: float = 990.0

@export var player_path: NodePath
@export var trains_path: NodePath
@export var camera_rig_path: NodePath
@export var hud_path: NodePath
@export var game_state_path: NodePath
@export var stations_path: NodePath  # 車内アナウンスの駅名引き当て用
@export var railway_path: NodePath   # 分岐ワープ時に乗り換え先ルート情報を引く

signal boarded(train_display_name: String)
signal alighted()

var _state: int = State.WALKING
var _current_train: Train = null
var _ride_camera: Camera3D = null
var _ride_view_idx: int = 0
var _toggle_cooldown: float = 0.0

var _player: CharacterBody3D
var _trains: Node3D
var _camera_rig: Node3D
var _hud: TouchHud
var _game_state: Node
var _stations: Node3D
var _railway: Node
var _chime: AudioStreamPlayer
var _chime_stream: AudioStreamWAV
var _reward: AudioStreamPlayer        # 「ぴったり とうちゃく」ごほうび音
var _reward_stream: AudioStreamWAV

# うんてんしゅモード状態
var _driving: bool = false            # 運転手モードか
var _shown_branch = null              # 現在表示中の分岐 dict(重複表示防止。null=非表示)
var _branch_cooldown: float = 0.0     # 乗り換え直後に逆方向分岐を即提示しないための猶予(秒)


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_trains = get_node_or_null(trains_path) as Node3D
	_camera_rig = get_node_or_null(camera_rig_path) as Node3D
	_hud = get_node_or_null(hud_path) as TouchHud
	_game_state = get_node_or_null(game_state_path)
	_stations = get_node_or_null(stations_path) as Node3D
	_railway = get_node_or_null(railway_path)
	_chime = AudioStreamPlayer.new()
	_chime.volume_db = -8.0
	add_child(_chime)
	_chime_stream = _make_chime()
	_reward = AudioStreamPlayer.new()
	_reward.volume_db = -8.0
	add_child(_reward)
	_reward_stream = _make_tone(PERFECT_STOP_TONE_A, PERFECT_STOP_TONE_B, 0.3)
	if _player == null:
		push_warning("[RideController] player_path が未解決")
	if _trains == null:
		push_warning("[RideController] trains_path が未解決")


func _process(delta: float) -> void:
	if _toggle_cooldown > 0.0:
		_toggle_cooldown = max(0.0, _toggle_cooldown - delta)

	# 歩行中は最寄りの乗れる電車を案内表示
	if _state == State.WALKING:
		_update_prompt()

	# 運転中は分岐への接近を監視(2択の表示/消去)
	if _branch_cooldown > 0.0:
		_branch_cooldown = max(0.0, _branch_cooldown - delta)
	if _driving:
		_check_branch()

	# キーボード(E/Enter)用。タッチボタンは touch_hud が toggle_ride() を直接呼ぶ
	# (タッチ/Web では action のリリース取りこぼしで押されっぱなしになり、2 回目の
	#  「押された瞬間」が検出されず降りられない事故があるため、pressed シグナル直結にした)。
	if Input.is_action_just_pressed("interact"):
		toggle_ride()


# いま電車に乗っているか(月旅行など、乗車中に発動してはいけない機能のガード用)。
func is_riding() -> bool:
	return _state == State.RIDING


# 乗降トグル(タッチボタンの pressed / キーボード interact の共通入口)。
# 歩行中なら最寄りの電車に乗り、乗車中なら降りる。直後の誤連打はクールダウンで防ぐ。
func toggle_ride() -> void:
	if _toggle_cooldown > 0.0:
		return
	if _state == State.WALKING:
		var train := _find_nearest_ridable()
		if train != null:
			_board(train)
			_toggle_cooldown = TOGGLE_DEBOUNCE
	else:
		_alight()
		_toggle_cooldown = TOGGLE_DEBOUNCE


# === 乗れる電車の検出 ===

func _find_nearest_ridable() -> Train:
	if _player == null or _trains == null:
		return null
	var trains := _trains.get_children()
	var positions: Array = []
	for t in trains:
		positions.append((t as Train).get_ride_anchor_position())
	var idx := _nearest_index(_player.global_position, positions, RIDE_RANGE)
	if idx < 0:
		return null
	return trains[idx] as Train


func _update_prompt() -> void:
	if _hud == null:
		return
	var train := _find_nearest_ridable()
	if train != null:
		_hud.show_board_prompt(train.get_display_name())
	else:
		_hud.hide_board_prompt()


# === 乗車 / 降車 ===

func _board(train: Train) -> void:
	_transition(func() -> void: _do_board(train))


func _do_board(train: Train) -> void:
	_state = State.RIDING
	_current_train = train

	if _player:
		_player.velocity = Vector3.ZERO
		_player.set_physics_process(false)
		_player.visible = false

	_ride_view_idx = 0
	_build_ride_camera(RIDE_VIEWS[_ride_view_idx])

	# 車内アナウンス: この編成の到着 / 発車を購読
	if not train.arrived.is_connected(_on_ride_arrived):
		train.arrived.connect(_on_ride_arrived)
	if not train.departed.is_connected(_on_ride_departed):
		train.departed.connect(_on_ride_departed)

	if _hud:
		_hud.hide_board_prompt()
		_hud.set_riding(true)
		_hud.show_notice("%sに のったよ!" % train.get_display_name())

	if _game_state:
		_game_state.add_boarded(train.get_slug())

	boarded.emit(train.get_display_name())


func _alight() -> void:
	_transition(func() -> void: _do_alight())


func _do_alight() -> void:
	var train := _current_train
	# 運転手モードを必ず解除(状態を歩行へ持ち越さない)
	if train and train.has_method("exit_driver_mode"):
		train.exit_driver_mode()
	_driving = false
	_shown_branch = null
	if _hud:
		_hud.hide_branch_choice()
		_hud.set_driving(false)
	# 車内アナウンスの購読を解除
	if train:
		if train.arrived.is_connected(_on_ride_arrived):
			train.arrived.disconnect(_on_ride_arrived)
		if train.departed.is_connected(_on_ride_departed):
			train.departed.disconnect(_on_ride_departed)
	if _player and train:
		var anchor: Vector3 = train.get_ride_anchor_position()
		var fwd: Vector3 = train.get_ride_forward()
		fwd.y = 0.0
		if fwd.length() > 0.001:
			fwd = fwd.normalized()
		else:
			fwd = Vector3.FORWARD
		var xz := _compute_landing(anchor, fwd, LANDING_OFFSET)
		var gy := TerrainHeight.compute_height(xz.x, xz.y) + PLAYER_GROUND_OFFSET
		_player.global_position = Vector3(xz.x, gy, xz.y)
		_player.visible = true
		_player.set_physics_process(true)

	# 乗車カメラを破棄し、元の追従カメラに戻す
	if _camera_rig:
		var main_cam := _camera_rig.get_node_or_null("Camera3D") as Camera3D
		if main_cam:
			main_cam.current = true
	if _ride_camera:
		_ride_camera.queue_free()
		_ride_camera = null

	_state = State.WALKING
	_current_train = null

	if _hud:
		_hud.set_riding(false)

	alighted.emit()


# === カメラ生成(Godot 操作層) ===

# 指定プリセットの乗車カメラを、対応するマウント(中央 / 先頭車)の子に生成。
# 既存カメラがあれば破棄してから作り、current=true で即時に切替える。
func _build_ride_camera(view: Dictionary) -> void:
	if _ride_camera:
		_ride_camera.queue_free()
		_ride_camera = null
	if _current_train == null:
		return
	var mount: Node3D
	if String(view["mount"]) == "front":
		mount = _current_train.get_ride_mount_front()
	else:
		mount = _current_train.get_ride_mount()
	if mount == null:
		return
	var cam := Camera3D.new()
	cam.fov = float(view["fov"])
	mount.add_child(cam)
	cam.position = view["pos"]
	cam.rotation = Vector3(deg_to_rad(float(view["pitch"])), deg_to_rad(float(view["yaw"])), 0.0)
	cam.current = true
	_ride_camera = cam


# 乗車中の視点を巡回(やね→うんてんせき→まどぎわ→…)。HUD の「ながめ」ボタンから。
# 切替の瞬間はフェードで隠す(酔わない・怖くない)。
func cycle_ride_view() -> void:
	if _state != State.RIDING or _current_train == null:
		return
	_ride_view_idx = (_ride_view_idx + 1) % RIDE_VIEWS.size()
	var view: Dictionary = RIDE_VIEWS[_ride_view_idx]
	_transition(func() -> void: _build_ride_camera(view))
	if _hud:
		_hud.show_notice("%s から ながめる" % String(view["name"]))


# === うんてんしゅモード(運転手になって すすむ・とまる・ぶんき) ===

# 運転手モードのトグル(HUD「うんてん」ボタンから)。乗車中のみ有効。
func toggle_driver_mode() -> void:
	if _state != State.RIDING or _current_train == null:
		return
	_driving = not _driving
	if _driving:
		if _current_train.has_method("enter_driver_mode"):
			_current_train.enter_driver_mode()
		# 没入感のため運転席視点へ寄せる(RIDE_VIEWS[1] = うんてんせき)
		_ride_view_idx = 1
		_transition(func() -> void: _build_ride_camera(RIDE_VIEWS[_ride_view_idx]))
		if _game_state and _game_state.has_method("set_drove_train"):
			_game_state.set_drove_train()  # ミッション「うんてんしゅに なろう」
		if _hud:
			_hud.set_driving(true)
			_hud.show_notice("きみが うんてんしゅ!")
	else:
		if _current_train.has_method("exit_driver_mode"):
			_current_train.exit_driver_mode()
		_shown_branch = null
		if _hud:
			_hud.set_driving(false)
			_hud.hide_branch_choice()
			_hud.show_notice("じどう うんてんに もどすよ")


# 「ゴー」: 進む(スロットル全開へ ease)
func driver_go() -> void:
	if _driving and _current_train and _current_train.has_method("set_driver_throttle"):
		_current_train.set_driver_throttle(1.0)
		if _hud:
			_hud.show_notice("しゅっぱつ!")


# 「とまれ」: 止まる(スロットル 0 へ ease)
func driver_stop() -> void:
	if _driving and _current_train and _current_train.has_method("set_driver_throttle"):
		_current_train.set_driver_throttle(0.0)


# 分岐への接近を監視。現編成のルートに自分の分岐があり、その手前に来たら2択を出す。
# 通り過ぎたら(接近窓を外れたら)消す = 何も選ばなければ直進(強制・失敗なし)。
func _check_branch() -> void:
	if _current_train == null or _hud == null or _branch_cooldown > 0.0:
		return
	# 実際に走っているルートの slug で分岐を照合(載り替え後も正しく検出するため)
	var slug: String = _current_train.get_route_slug()
	var here: float = _current_train.get_progress_ratio()
	var active = null
	for b in RouteData.branches():
		if String(b["from"]) != slug:
			continue
		var d: float = _ratio_ahead(here, float(b["at_ratio"]))
		if d <= BRANCH_PREVIEW_RATIO:
			active = b
			break
	if active != null:
		if _shown_branch != active:
			_offer_branch(active)
	elif _shown_branch != null:
		_shown_branch = null
		_hud.hide_branch_choice()


# 2択を HUD に提示(行き先の電車名・色を渡す)。行き先ルートに今いる編成の名前/色を使う。
func _offer_branch(b: Dictionary) -> void:
	_shown_branch = b
	var to_train := _find_train_on_route(String(b["to"]), _current_train)
	var to_name: String = to_train.get_display_name() if to_train else "となりの でんしゃ"
	var to_color: Color = Color.WHITE
	if to_train and to_train.train_data:
		to_color = to_train.train_data.body_color
	_hud.show_branch_choice(to_name, to_color)


# 乗り換え(2択の「のりかえる」側が押された)。
# 二重編成を避けるため「ルート入れ替え方式」: 運転中の編成を行き先ルートへ載せ替えると同時に、
# 行き先ルートに元からいた編成を、こちらが抜けた元ルートへ載せ替える(両者をスワップ)。
# これで「1ルート1編成」が常に保たれ、線路がカラになったり編成が重なったりしない。
# 両方の reparent はフェードの中点(画面が隠れている間)で実行するので、瞬間移動は見えない。
func take_branch() -> void:
	if _shown_branch == null or _current_train == null:
		return
	var b: Dictionary = _shown_branch
	_shown_branch = null
	_hud.hide_branch_choice()
	if _railway == null or not _railway.has_method("get_route_path"):
		return
	var driven: Train = _current_train
	var from_slug: String = driven.get_route_slug()
	var to_slug: String = String(b["to"])
	# 行き先・元ルートの情報を取得
	var to_path: Path3D = _railway.get_route_path(to_slug)
	var to_len: float = _railway.get_route_length(to_slug)
	var to_stops: Array = _railway.get_route_stops(to_slug)
	var from_path: Path3D = _railway.get_route_path(from_slug)
	var from_len: float = _railway.get_route_length(from_slug)
	var from_stops: Array = _railway.get_route_stops(from_slug)
	if to_path == null or to_len <= 0.0 or from_path == null or from_len <= 0.0:
		return
	# 行き先ルートに今いる編成(入れ替え相手)
	var resident: Train = _find_train_on_route(to_slug, driven)
	var to_prog: float = float(b["to_ratio"]) * to_len      # 運転編成の新位置(分岐点)
	var from_prog: float = float(b["at_ratio"]) * from_len  # 相手編成を置く位置(元ルートの分岐点)
	_branch_cooldown = 3.0
	_transition(func() -> void:
		if driven and driven.has_method("switch_route"):
			driven.switch_route(to_slug, to_path, to_prog, to_len, to_stops, _route_speed(driven, to_len))
		if resident and resident.has_method("switch_route"):
			resident.switch_route(from_slug, from_path, from_prog, from_len, from_stops, _route_speed(resident, from_len)))
	if _hud:
		var label := resident.get_display_name() if resident else to_slug
		_hud.show_notice("%s の せんろへ!" % label)


# 直進(2択の「このまま まっすぐ」側が押された)。何もせず2択を畳むだけ。
func keep_straight() -> void:
	_shown_branch = null
	if _hud:
		_hud.hide_branch_choice()


# === うんてんしゅモード ヘルパ ===

# 前方向きの ratio 差(0..1)。0 に近い = もうすぐ到達。通過した瞬間 ~1.0 に跳ねる。
func _ratio_ahead(here: float, at: float) -> float:
	return fposmod(at - here, 1.0)


# いま指定ルート(slug)を走っている編成を返す(exclude は除外。なければ null)。
# 「1ルート1編成」なので通常1本。分岐スワップの入れ替え相手を見つけるのに使う。
func _find_train_on_route(slug: String, exclude: Train = null) -> Train:
	if _trains == null:
		return null
	for t in _trains.get_children():
		if t == exclude:
			continue
		if t.has_method("get_route_slug") and (t as Train).get_route_slug() == slug:
			return t as Train
	return null


# 線速度(m/s)を train_data.speed と周長から算出。train_data が無ければ既定値。
func _route_speed(train: Train, length: float) -> float:
	if train and train.train_data and length > 0.0:
		return train.train_data.speed * length / TAU
	return 1.0


# === 車内アナウンス(乗車中の編成の到着 / 発車で呼ばれる) ===

func _on_ride_arrived(anchor_pos: Vector3) -> void:
	# 添え: 自分で減速して駅にぴたっと止めたら「ぴったり とうちゃく!」のごほうび。
	# (止めなくても下の通常到着通知が出るだけ。失敗概念はない)
	if _driving and _current_train and _current_train.is_driver_stopped():
		if _hud:
			_hud.show_notice("ぴったり とうちゃく!")
		if _reward and _reward_stream:
			_reward.stream = _reward_stream
			_reward.play()
		if _game_state and _game_state.has_method("add_star"):
			_game_state.add_star()  # 公平に良い結果へ寄せる
		return
	var name := _nearest_station_name(anchor_pos)
	if name != "" and _hud:
		_hud.show_notice("%s えき に とうちゃく!" % name)
	# 到着音は StationManager の駅メロが鳴らすので、ここではチャイムを重ねない


func _on_ride_departed() -> void:
	if _hud:
		_hud.show_notice("しゅっぱつ しんこう!")
	if _chime and _chime_stream:
		_chime.stream = _chime_stream
		_chime.play()


# 到着位置に最も近い駅の表示名(なければ "")
func _nearest_station_name(pos: Vector3) -> String:
	if _stations == null:
		return ""
	var best_name := ""
	var best_d := ANNOUNCE_NEAR_STATION
	for child in _stations.get_children():
		if not child.has_method("get_display_name"):  # Station ノードだけ対象
			continue
		var d: float = (child as Node3D).global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best_name = child.get_display_name()
	return best_name


# 発車チャイム(ピンポーン: 高→低の 2 音)を正弦波で生成
func _make_chime() -> AudioStreamWAV:
	return _make_tone(988.0, 740.0, 0.32)


func _make_tone(freq_a: float, freq_b: float, dur: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / float(MIX_RATE)
		var prog: float = float(i) / float(n)
		var freq: float = freq_a if prog < 0.5 else freq_b
		var env: float = sin(prog * PI)
		var s: float = sin(TAU * freq * t) * env * 0.55
		var v: int = int(clamp(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


# === フェード遷移(Godot 操作層) ===

# やさしいフェードを噛ませ、中点で midpoint を実行してカメラ切替の瞬間を隠す。
func _transition(midpoint: Callable) -> void:
	if _hud == null:
		midpoint.call()
		return
	var tw := create_tween()
	tw.tween_method(Callable(_hud, "set_fade_alpha"), 0.0, 1.0, FADE_TIME)
	tw.tween_callback(midpoint)
	tw.tween_method(Callable(_hud, "set_fade_alpha"), 1.0, 0.0, FADE_TIME)


# === ロジック層(言語非依存・テスト可能) ===

# positions の中で player_pos に最も近く、かつ max_range 以内の index。無ければ -1。
static func _nearest_index(player_pos: Vector3, positions: Array, max_range: float) -> int:
	var best: int = -1
	var best_d: float = max_range * max_range
	for i in range(positions.size()):
		var d: float = player_pos.distance_squared_to(positions[i])
		if d <= best_d:
			best_d = d
			best = i
	return best


# 降車地点(x, z)を計算。線路中心 anchor から進行方向 forward に直交する向きで、
# 楕円中心(原点)から離れる外側へ side_offset ずらす(電車・レール・枕木に埋まらない)。
static func _compute_landing(anchor: Vector3, forward: Vector3, side_offset: float) -> Vector2:
	var perp: Vector3 = forward.cross(Vector3.UP).normalized()
	var perp_xz: Vector2 = Vector2(perp.x, perp.z)
	var anchor_xz: Vector2 = Vector2(anchor.x, anchor.z)
	var outward: Vector3 = perp if perp_xz.dot(anchor_xz) >= 0.0 else -perp
	var landing: Vector3 = anchor + outward * side_offset
	return Vector2(landing.x, landing.z)
