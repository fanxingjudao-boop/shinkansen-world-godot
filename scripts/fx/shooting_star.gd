extends Node3D

# 流れ星。夜になるとときどき、プレイヤーの上空を斜めにスーッと横切る。
# 見つけたら「おねがいごと…」のやさしいテロップが出る(良いことが起きる予感=怖くない演出)。
# 地上の「集める星」(stars.gd)とは別物の、空の演出。Main 直下のノード。

const TouchHud = preload("res://scripts/ui/touch_hud.gd")

const NIGHT_LO: float = 0.22
const NIGHT_HI: float = 0.80
const INTERVAL_MIN: float = 9.0      # 次の流れ星までの最短(秒)
const INTERVAL_MAX: float = 22.0     # 〃 最長
const STAR_COLOR: Color = Color(1.0, 0.95, 0.7)
const TRAVEL_SEC: float = 1.15       # 横切るのにかかる時間
const STREAK_LEN: float = 6.0        # 尾の長さ

@export var day_night_path: NodePath
@export var player_path: NodePath
@export var hud_path: NodePath

var _dn: Node
var _player: Node3D
var _hud: TouchHud
var _timer: float = 6.0
var _active: bool = false


func _ready() -> void:
	_dn = get_node_or_null(day_night_path)
	_player = get_node_or_null(player_path) as Node3D
	_hud = get_node_or_null(hud_path) as TouchHud
	_timer = randf_range(4.0, 10.0)  # 最初の流れ星まで少し待つ


func _process(delta: float) -> void:
	if _active:
		return
	if not _is_night():
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = randf_range(INTERVAL_MIN, INTERVAL_MAX)
		_spawn()


func _is_night() -> bool:
	if _dn == null:
		return true
	var t: float = _dn.time_of_day
	return t < NIGHT_LO or t > NIGHT_HI


func _spawn() -> void:
	_active = true
	var center: Vector3 = _player.global_position if _player else Vector3.ZERO
	var side: float = 1.0 if randf() < 0.5 else -1.0
	var span: float = 70.0
	var zoff: float = randf_range(-30.0, 30.0)
	var start: Vector3 = center + Vector3(-side * span * 0.5, 65.0, zoff)
	var end: Vector3 = center + Vector3(side * span * 0.5, 40.0, zoff + randf_range(-15.0, 15.0))

	var streak := _make_streak()
	add_child(streak)
	streak.global_position = start
	streak.look_at(start + (end - start), Vector3.UP)  # 尾を進行方向に向ける(-Z が進む先)

	if _hud:
		_hud.show_notice("ながれぼし! おねがいごと…")

	var tw := create_tween()
	tw.tween_property(streak, "global_position", end, TRAVEL_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# 進みながらだんだん消える(transparency 0=見える → 1=透明)
	tw.parallel().tween_property(streak, "transparency", 1.0, TRAVEL_SEC) \
		.set_ease(Tween.EASE_IN)
	tw.tween_callback(streak.queue_free)
	tw.tween_callback(func() -> void: _active = false)


# 光る頭(細長い尾)。ローカル -Z 方向が進む先(尾は +Z 側に伸びる)。
func _make_streak() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.45, 0.45, STREAK_LEN)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STAR_COLOR
	mat.emission_enabled = true
	mat.emission = STAR_COLOR
	mat.emission_energy_multiplier = 2.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	return mi
