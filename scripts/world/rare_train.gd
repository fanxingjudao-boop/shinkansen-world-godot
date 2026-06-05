extends Node3D

# B-7 かくれた でんしゃ(レア車両)。PLAYFUL_DETAILS B-7。
# 夜(time_of_day < 0.22 または > 0.80。ホタル/流れ星と同じ判定)だけ、にじいろの
# 「ゆめ」しんかんせんが専用ルート(route_data の "yume")に現れて走る。昼になると消える。
# 見つけて乗ると図鑑の隠し枠が うまる(発見=乗車=他の電車と同じ。has_train("yume"))。
#
# 設計(SPEC.md / 寄生方式):
# - Main 直下に 1 つ置く小さなノード(main.gd が起動時に _spawn_extra で生成)。Main.tscn は不変。
# - 列車は既存の Train.tscn を instance し、Trains ノードに足す → 乗車・図鑑・すれ違いに自動波及。
#   専用ルートなので他編成と衝突しない(route_data 参照)。
# - 子供配慮: 夜になれば必ず出る(優しい条件)。怖くない・見つけられなくても損しない。

const TRAIN_SCENE = preload("res://scenes/entities/Train.tscn")
const YUME_DATA = preload("res://resources/train_data/yume.tres")

const NIGHT_LO: float = 0.22   # fireflies.gd / shooting_star.gd と同じ夜判定
const NIGHT_HI: float = 0.80
const CHECK_INTERVAL: float = 0.5

var _railway: Node = null
var _trains: Node = null
var _dn: Node = null
var _gs: Node = null
var _ride: Node = null
var _train: Node3D = null
var _timer: float = 0.0
var _celebrated: bool = false


func _ready() -> void:
	_resolve()


func _resolve() -> bool:
	var root := get_tree().root
	if _railway == null:
		_railway = root.find_child("Railway", true, false)
	if _trains == null:
		_trains = root.find_child("Trains", true, false)
	if _dn == null:
		_dn = root.find_child("DayNightCycle", true, false)
	if _gs == null:
		_gs = root.find_child("GameState", true, false)
	if _ride == null:
		_ride = root.find_child("RideController", true, false)
	return _railway != null and _trains != null and _dn != null


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	if not _resolve():
		return

	var t: float = _dn.time_of_day
	var night: bool = t < NIGHT_LO or t > NIGHT_HI
	if night and _train == null:
		_spawn()
	elif not night and _train != null:
		_despawn()

	# 発見のお祝い(初回だけ)。乗車で has_train("yume") になった瞬間。
	if not _celebrated and _gs != null and _gs.has_method("has_train") and _gs.has_train("yume"):
		_celebrated = true
		var hud := get_tree().root.find_child("TouchHUD", true, false)
		if hud and hud.has_method("show_notice"):
			hud.show_notice("ゆめの でんしゃ みつけた!")
		if _gs.has_method("add_star"):
			_gs.add_star()  # ごほうび(ほし +1)


func _spawn() -> void:
	_train = TRAIN_SCENE.instantiate()
	_train.name = "Yume"
	_train.train_data = YUME_DATA
	_train.railway_path = _railway.get_path()  # 絶対パス(どこに足しても解決)
	_trains.add_child(_train)


func _despawn() -> void:
	# プレイヤーが ゆめ電車に乗車中なら、降りるまで消さない(乗車を壊さない)。
	if _ride != null and _ride.has_method("get_current_train") and _ride.get_current_train() == _train:
		return
	_train.queue_free()
	_train = null
