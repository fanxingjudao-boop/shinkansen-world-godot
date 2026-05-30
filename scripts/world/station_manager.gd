extends Node3D

# 駅の「はっけん」を統括する。Stations ノードに付ける。
# - プレイヤーが駅に近づいたら自動で発見(タッチ不要、動物のなかよしと同じ方式)
# - 発見で GameState に記録 + HUD に「○○ えき はっけん!」通知
# - 発見済み判定は GameState.has_station() で行う(重複通知を防ぐ)

const Station = preload("res://scripts/world/station.gd")
const TouchHud = preload("res://scripts/ui/touch_hud.gd")

const FIND_RANGE: float = 9.0  # 駅は大きいので広め

@export var player_path: NodePath
@export var hud_path: NodePath
@export var game_state_path: NodePath

signal discovered(display_name: String, total: int)

var _player: Node3D
var _hud: TouchHud
var _game_state: Node


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	_hud = get_node_or_null(hud_path) as TouchHud
	_game_state = get_node_or_null(game_state_path)


func _process(_delta: float) -> void:
	if _player == null or _game_state == null:
		return
	var pp: Vector3 = _player.global_position
	for child in get_children():
		var s := child as Station
		if s == null:
			continue
		var slug := s.get_slug()
		if _game_state.has_station(slug):
			continue
		if s.global_position.distance_to(pp) < FIND_RANGE:
			_game_state.add_station(slug)
			if _hud:
				_hud.show_notice("%s えき はっけん!" % s.get_display_name())
			discovered.emit(s.get_display_name(), _game_state.visited_stations.size())
