extends Node

# やさしいミッション。Main 直下のノード。
# GameState の進捗を見て、いまのミッションが達成されたら次へ進む。
# 失敗・制限時間・ゲームオーバーは一切なし。順にクリアして「やったね!」を増やす。

const GameState = preload("res://scripts/world/game_state.gd")
const TouchHud = preload("res://scripts/ui/touch_hud.gd")

@export var game_state_path: NodePath
@export var hud_path: NodePath

var _gs: GameState
var _hud: TouchHud
var _idx: int = 0
var _missions: Array = []


func _ready() -> void:
	_gs = get_node_or_null(game_state_path) as GameState
	_hud = get_node_or_null(hud_path) as TouchHud
	# 前半は基本(乗る・なかよし・あつめる・えき)、後半は作り込んだ目玉へ誘導する
	# 「ツアー」: うんてんしゅ・おしろ・つき。子供が宝物を確実に見つけられるように。
	_missions = [
		{"text": "でんしゃに のってみよう", "done": func() -> bool: return _gs.boarded_trains.size() >= 1},
		{"text": "どうぶつと なかよしに なろう", "done": func() -> bool: return _gs.befriended_animals.size() >= 1},
		{"text": "ほしを 3こ あつめよう", "done": func() -> bool: return _gs.star_count >= 3},
		{"text": "えきを みつけよう", "done": func() -> bool: return _gs.visited_stations.size() >= 1},
		{"text": "「うんてん」ボタンで うんてんしゅに なろう", "done": func() -> bool: return _gs.drove_train},
		{"text": "おしろの でんしゃに のろう", "done": func() -> bool: return "oshiro" in _gs.boarded_trains},
		{"text": "ロケットで つきへ いこう", "done": func() -> bool: return _gs.visited_moon},
		{"text": "ひこうきで そらの おしろへ いこう", "done": func() -> bool: return _gs.visited_sky_castle},
		{"text": "せんすいかんで うみの そこへ いこう", "done": func() -> bool: return _gs.visited_submarine},
		{"text": "おかしの きしゃで おかしの くにへ いこう", "done": func() -> bool: return _gs.visited_candy},
		{"text": "ほしを 9こ あつめよう", "done": func() -> bool: return _gs.star_count >= 9},
	]
	# ロード済みで達成済みのミッションは通知なしでスキップ
	if _gs:
		while _idx < _missions.size() and _missions[_idx]["done"].call():
			_idx += 1
		_gs.changed.connect(_on_changed)
	# タイトルの「はじめる」で、最初のミッションをやさしく通知して導線にする
	# (パネルは従来どおり「メニュー」で開ける=常時表示にはしない)。
	var title := get_tree().root.find_child("TitleScreen", true, false)
	if title and title.has_signal("started"):
		title.started.connect(_on_started)
	# HUD(TouchHUD)は後から _ready するので、表示は遅延して反映する
	call_deferred("_update_hud")


func _on_started() -> void:
	_announce("ミッション: ")


func _on_changed() -> void:
	_check()


func _check() -> void:
	var cleared := false
	while _idx < _missions.size() and _missions[_idx]["done"].call():
		_idx += 1
		cleared = true
		if _hud:
			_hud.show_notice("ミッション クリア!")
		_update_hud()
	# クリアの「やったね」の少しあとに、次の目標を通知で案内(連続表示で潰れないよう遅らせる)
	if cleared:
		_announce_delayed("つぎは: ", 2.2)


func _update_hud() -> void:
	if _hud == null:
		return
	if _idx < _missions.size():
		_hud.set_mission(_missions[_idx]["text"])
	else:
		_hud.set_mission("ぜんぶ クリア!すごいね!")


# いまのミッションを通知で出す(prefix 例: 「ミッション: 」「つぎは: 」)。
func _announce(prefix: String) -> void:
	if _hud == null:
		return
	if _idx < _missions.size():
		_hud.show_notice(prefix + _missions[_idx]["text"])
	else:
		_hud.show_notice("ぜんぶ クリア!すごいね!")


func _announce_delayed(prefix: String, secs: float) -> void:
	await get_tree().create_timer(secs).timeout
	_announce(prefix)
