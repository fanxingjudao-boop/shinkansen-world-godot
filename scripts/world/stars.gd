extends Node3D

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")
const TouchHud = preload("res://scripts/ui/touch_hud.gd")

# 集める星 12 個。
# 地形上のランダム位置に固定配置(seed で毎回同じ → 子供が「あの星」と認識できる)。
# 常時きらきら光って浮遊・回転し、プレイヤーが近づくと獲得(タッチ不要=動物のなかよしと同じやさしい方式)。
# 獲得で GameState.add_star + HUD 通知 + ぴょこっと消える演出。

const STAR_COUNT: int = 18
const STAR_SIZE: float = 0.55
const STAR_COLOR: Color = Color(1.0, 0.88, 0.4)
const PLACE_RADIUS: float = 120.0
const HEIGHT_OFFSET: float = 1.6
const SPIN_SPEED: float = 1.2
const FLOAT_AMP: float = 0.3
const FLOAT_FREQ: float = 1.5
const GET_RANGE: float = 2.6
const STAR_SEED: int = 42

@export var player_path: NodePath
@export var game_state_path: NodePath
@export var hud_path: NodePath

var _player: Node3D
var _game_state: Node
var _hud: TouchHud
var _stars: Array = []  # 各要素: {node, base_y, phase, taken}


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	_game_state = get_node_or_null(game_state_path)
	_hud = get_node_or_null(hud_path) as TouchHud

	seed(STAR_SEED)
	var base_mat: StandardMaterial3D = _make_star_material()
	for i in range(STAR_COUNT):
		var mat: StandardMaterial3D = base_mat.duplicate()  # 星ごとに脈動させるため複製
		var node := _make_star(mat)
		var x: float = randf_range(-PLACE_RADIUS, PLACE_RADIUS)
		var z: float = randf_range(-PLACE_RADIUS, PLACE_RADIUS)
		var gy: float = TerrainHeight.compute_height(x, z) + HEIGHT_OFFSET
		node.position = Vector3(x, gy, z)
		add_child(node)
		_stars.append({"node": node, "base_y": gy, "phase": randf_range(0.0, TAU), "taken": false, "mat": mat})


func _process(delta: float) -> void:
	var pp: Vector3 = _player.global_position if _player else Vector3.ZERO
	for st in _stars:
		if st.taken:
			continue
		var node: Node3D = st.node
		node.rotate_y(SPIN_SPEED * delta)
		st.phase += delta * FLOAT_FREQ
		node.position.y = st.base_y + sin(st.phase) * FLOAT_AMP
		st.mat.emission_energy_multiplier = 2.2 + sin(st.phase * 2.5) * 1.3  # きらきら脈動
		if _player and node.global_position.distance_to(pp) < GET_RANGE:
			_collect(st)


# === 獲得 ===

func _collect(st: Dictionary) -> void:
	st.taken = true
	var node: Node3D = st.node
	_spawn_burst(node.global_position)
	if _game_state:
		_game_state.add_star()
	if _hud:
		_hud.show_notice("ほしを ゲット!")
	# ぴょこっと拡大 → 上に飛んで縮んで消える
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 1.8, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ZERO, 0.3)
	tw.parallel().tween_property(node, "position:y", st.base_y + 2.5, 0.3)
	tw.tween_callback(node.queue_free)


# 獲得時にキラキラを一発はじけさせる(GPUParticles3D one-shot、寿命後 自動削除)
func _spawn_burst(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, -4.0, 0)
	pm.scale_min = 0.15
	pm.scale_max = 0.4
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STAR_COLOR
	mat.emission_enabled = true
	mat.emission = STAR_COLOR
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


# === メッシュ構築 ===

func _make_star_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STAR_COLOR
	mat.emission_enabled = true
	mat.emission = STAR_COLOR
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _make_star(mat: StandardMaterial3D) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = STAR_SIZE
	sphere.height = STAR_SIZE * 2.0
	sphere.radial_segments = 6  # 8 面体っぽくキラキラ感
	sphere.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	return mi
