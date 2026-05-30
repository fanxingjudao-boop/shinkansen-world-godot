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
	_missions = [
		{"text": "でんしゃに のってみよう", "done": func() -> bool: return _gs.boarded_trains.size() >= 1},
		{"text": "どうぶつと なかよしに なろう", "done": func() -> bool: return _gs.befriended_animals.size() >= 1},
		{"text": "ほしを 3こ あつめよう", "done": func() -> bool: return _gs.star_count >= 3},
		{"text": "えきを みつけよう", "done": func() -> bool: return _gs.visited_stations.size() >= 1},
		{"text": "ほしを 6こ あつめよう", "done": func() -> bool: return _gs.star_count >= 6},
	]
	if _gs:
		_gs.changed.connect(_on_changed)
	_update_hud()


func _on_changed() -> void:
	_check()


func _check() -> void:
	while _idx < _missions.size() and _missions[_idx]["done"].call():
		_idx += 1
		if _hud:
			_hud.show_notice("ミッション クリア!")
		_update_hud()


func _update_hud() -> void:
	if _hud == null:
		return
	if _idx < _missions.size():
		_hud.set_mission(_missions[_idx]["text"])
	else:
		_hud.set_mission("ぜんぶ クリア!すごいね!")
