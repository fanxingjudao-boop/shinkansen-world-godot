extends Node3D

# A-5 遊び心「電車の窓から乗客が手を振る」のすれ違い検知ノード。
# main.gd の _spawn_extra で Main 直下に生成され、Main.tscn は変更しない(load_steps 据え置き)。
#
# 各 Train は他編成や Player を知らない疎結合設計のため、横断ロジック(誰のそばを誰が通るか)を
# ここに集約する(animal_manager / reward_manager と同じ役割分担)。実際の手振り見た目と
# クールダウンは train.gd の wave_passengers() が持つ。ここは「すれ違ったら呼ぶ」だけ。
#
# 観測者:
#   - 乗車中 → 乗っている編成のアンカー(=自分が振られる側。乗る編成自身は除外)
#   - 歩行中 → プレイヤーの位置
# 観測者の GREET_RANGE 以内を通る編成に wave_passengers() を呼ぶ(連発は train 側のクールダウンで防ぐ)。

const GREET_RANGE: float = 45.0       # この距離以内ですれ違い=手を振る(甘め判定)
const CHECK_INTERVAL: float = 0.2     # 検知間隔(秒)。毎フレームは不要

var _player: Node3D = null
var _rc: Node = null                  # RideController
var _trains: Node = null
var _timer: float = 0.0


func _ready() -> void:
	_resolve()


# Player / RideController / Trains を探す。起動直後はまだ居ない可能性があるので
# 取れなければ _process 側で取れるまで再試行する(train.gd の遅延初期化と同じ思想)。
func _resolve() -> bool:
	var root := get_tree().root
	if _player == null:
		_player = root.find_child("Player", true, false) as Node3D
	if _rc == null:
		_rc = root.find_child("RideController", true, false)
	if _trains == null:
		_trains = root.find_child("Trains", true, false)
	return _player != null and _trains != null


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL

	if not _resolve():
		return

	# 観測者位置を決める。
	var ridden: Node = null
	if _rc != null and _rc.has_method("get_current_train"):
		ridden = _rc.get_current_train()
	var observer: Vector3
	if ridden != null and ridden.has_method("get_ride_anchor_position"):
		observer = ridden.get_ride_anchor_position()
	else:
		observer = _player.global_position

	# 観測者のそばを通る編成に手を振らせる。
	for t in _trains.get_children():
		if t == ridden:
			continue  # 自分が乗っている編成は除外
		if not t.has_method("get_ride_anchor_position") or not t.has_method("wave_passengers"):
			continue
		var d: float = (t.get_ride_anchor_position() as Vector3).distance_to(observer)
		if d <= GREET_RANGE:
			t.wave_passengers()  # train 側のクールダウンで連発は防がれる
