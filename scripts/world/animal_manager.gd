extends Node3D

# 動物たちの「なかよし」を統括する。Animals ノードに付ける。
# - プレイヤーが動物に近づいたら自動でなかよし成立(タッチ不要=3歳児にやさしい)
# - interact を使わないので乗車システム(ride_controller)と競合しない
# - なかよし成立で動物が喜び、HUD に「○○と なかよし!」通知
# - なかよし数は signal で公開(将来の HUD カウンター / 図鑑用)

const Animal = preload("res://scripts/entities/animal.gd")
const TouchHud = preload("res://scripts/ui/touch_hud.gd")

const BEFRIEND_RANGE: float = 3.0

@export var player_path: NodePath
@export var hud_path: NodePath
@export var game_state_path: NodePath

signal befriended(display_name: String, total: int)

var _player: Node3D
var _hud: TouchHud
var _game_state: Node
var _count: int = 0


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	_hud = get_node_or_null(hud_path) as TouchHud
	_game_state = get_node_or_null(game_state_path)
	if _player == null:
		push_warning("[AnimalManager] player_path が未解決")


func _process(_delta: float) -> void:
	if _player == null:
		return
	var pp: Vector3 = _player.global_position
	for child in get_children():
		var a := child as Animal
		if a == null or a.is_befriended():
			continue
		if a.global_position.distance_to(pp) < BEFRIEND_RANGE:
			a.befriend()
			_count += 1
			if _hud:
				_hud.show_notice("%sと なかよし!" % a.get_display_name())
			if _game_state:
				_game_state.add_befriended(a.get_slug())
			befriended.emit(a.get_display_name(), _count)
