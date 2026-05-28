class_name DayNightCycle
extends Node

# 時刻を進めて空・太陽・環境光を更新する。
# 色計算は SkyColor(static)に分離(scripts/world/sky_color.gd)。
# class_name は Godot エディタが project を再スキャンするまで CLI で
# 認識されないため、preload で同名参照を作って両対応にする。

const SkyColor = preload("res://scripts/world/sky_color.gd")

const CYCLE_SEC: float = 84.0           # 1 サイクル(Three.js 版と同じテンポ)
const SUN_RADIUS: float = 80.0
const SUN_HEIGHT_OFFSET: float = 5.0
const SUN_Z: float = 30.0

@export var world_env_path: NodePath
@export var sun_path: NodePath
@export_range(0.0, 1.0, 0.01) var initial_time: float = 0.4  # 0.4 = 昼の始まり
@export var paused: bool = false  # デバッグ用に時刻を止められる

var time_of_day: float = 0.4:
	set(value):
		time_of_day = fposmod(value, 1.0)
		if is_inside_tree():
			_apply_time()

var _world_env: WorldEnvironment
var _sun: DirectionalLight3D


func _ready() -> void:
	time_of_day = initial_time
	if not world_env_path.is_empty():
		_world_env = get_node_or_null(world_env_path) as WorldEnvironment
	if not sun_path.is_empty():
		_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_apply_time()


func _process(delta: float) -> void:
	if paused:
		return
	time_of_day = fmod(time_of_day + delta / CYCLE_SEC, 1.0)
	_apply_time()


# === Godot 操作層 ===

func _apply_time() -> void:
	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.background_color = SkyColor.background(time_of_day)
		env.ambient_light_color = SkyColor.ambient(time_of_day)
		env.ambient_light_energy = SkyColor.ambient_energy(time_of_day)
		env.fog_light_color = SkyColor.fog_color(time_of_day)
	if _sun:
		_sun.global_position = SkyColor.sun_position(
			time_of_day, SUN_RADIUS, SUN_HEIGHT_OFFSET, SUN_Z
		)
		_sun.look_at(Vector3.ZERO)
		_sun.light_color = SkyColor.sun_color(time_of_day)
		_sun.light_energy = SkyColor.sun_energy(time_of_day)
