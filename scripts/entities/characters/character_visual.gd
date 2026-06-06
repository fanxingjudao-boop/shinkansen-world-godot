extends Node3D

# キャラクターの「見た目」の基底クラス。
# 主人公を選べるようにするための共通土台(うんてんしさん / キツネ などが継承)。
#
# player.gd は移動・物理だけを持ち、見た目とアニメをこのクラス(の子孫)に委譲する。
# 新しい主人公を増やすときは、このクラスを継承して build()/animate_walk()/wave() を
# 実装し、character_roster.gd に1行足すだけでよい(player/title は触らなくて済む)。
#
# 各キャラは自分のノード(= self)直下に見た目を組み立てる。player は self を
# 回転させて進行方向を向く(顔は -Z 向きに統一すること)。
# 歩行の上下バウンスは self.position.y、よろこびは self.scale で表す(競合しない)。

const RIM_SHADER = preload("res://assets/shaders/rim.gdshader")

# 歩行アニメの位相と「手を振っている最中」フラグ(子クラスが使う)。
var _walk_phase: float = 0.0
var _waving: bool = false


# 見た目を組み立てる(子クラスで override)。
func build() -> void:
	pass


# 毎フレームの歩行アニメ(子クラスで override)。moving=移動中かどうか。
func animate_walk(_delta: float, _moving: bool) -> void:
	pass


# 「てをふる」(子クラスで override)。なにもしないのが既定。
func wave() -> void:
	pass


# おだんご等の「やったね!」のぴょこっと喜び(scale バウンス)。
# 歩行アニメは position.y を、これは scale を触るので競合しない。共通実装。
func celebrate() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.25, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# === パーツ生成ヘルパー(子クラス共通) ===

# リムライト付き(輪郭がふんわり光る)。トゥーン調の本体パーツに使う。
func _add_part(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var sm := ShaderMaterial.new()
	sm.shader = RIM_SHADER
	sm.set_shader_parameter("albedo", color)
	sm.set_shader_parameter("roughness_val", 0.7)
	sm.set_shader_parameter("rim_color", Color(1, 1, 0.96))
	sm.set_shader_parameter("rim_power", 2.5)
	sm.set_shader_parameter("rim_strength", 0.5)
	mi.material_override = sm
	mi.position = pos
	parent.add_child(mi)
	return mi


# UNSHADED(目・ほっぺ・鼻のツヤなど、陰の影響を受けず鮮やかに)。
func _add_unshaded(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# 半透明 UNSHADED(ほっぺの赤み・ひげなど)。
func _add_unshaded_alpha(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
