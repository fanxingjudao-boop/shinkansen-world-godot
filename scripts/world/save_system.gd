extends Node

# 進捗の保存/読込。Main 直下、GameState の直後に置く(他のノードより先に読込を済ませ、
# HUD/ミッション/効果音が _ready で正しい初期値を読めるようにする)。
# Web では user:// が IndexedDB に永続化されるので、次に開いたとき続きから遊べる。
#
# 読込では changed を emit しない(値だけセット)。各 listener は自分の _ready で
# GameState の現在値を反映する。これで起動時に効果音が誤発火しない。

const GameState = preload("res://scripts/world/game_state.gd")
const SAVE_PATH: String = "user://save.json"

@export var game_state_path: NodePath

var _gs: GameState


func _ready() -> void:
	_gs = get_node_or_null(game_state_path) as GameState
	if _gs == null:
		push_warning("[SaveSystem] game_state_path が未解決")
		return
	_load()
	_gs.changed.connect(_save)


func _save() -> void:
	if _gs == null:
		return
	var d := {
		"star_count": _gs.star_count,
		"boarded": _gs.boarded_trains,
		"befriended": _gs.befriended_animals,
		"stations": _gs.visited_stations,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	_gs.star_count = int(d.get("star_count", 0))
	_gs.boarded_trains = _to_str_array(d.get("boarded", []))
	_gs.befriended_animals = _to_str_array(d.get("befriended", []))
	_gs.visited_stations = _to_str_array(d.get("stations", []))


func _to_str_array(a: Variant) -> Array[String]:
	var out: Array[String] = []
	if a is Array:
		for x in a:
			out.append(str(x))
	return out
