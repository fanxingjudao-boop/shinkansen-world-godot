extends RefCounted

# Main 配下の「必ず居るはずのノード」を find_child で取り、
# 見つからなければ push_warning する小道具。
#
# ねらい: 別世界スクリプト(moon_trip 等)は起動時に Player / CameraRig など
# Main.tscn 常駐ノードを find_child で集める。これまでは null でも無言だったので、
# 配線ミス(ノード名変更・Main.tscn 改変)を早期に気づけるよう警告を一本化する。
# コア系(train/animal/station 等)が既に使っている push_warning("[名前] …") 規約に揃える。
#
# 使い方(preload で取り込む。class_name は新規だと --check-only で未登録になりうるため使わない):
#   const WorldRefs = preload("res://scripts/world/world_refs.gd")
#   _player = WorldRefs.req(root, "Player", "Moon") as CharacterBody3D
#
# 注意: 任意ノード(常に居るとは限らない物)には使わない。例:
#   - CherryPetals … v0.42.0 で削除済=常に null。素の find_child のままにする。
#   - 各世界の HUD ボタン … 既に if _btn: ガード済 / ginga は実行時生成。素のままにする。

static func req(root: Node, node_name: String, owner_tag: String) -> Node:
	var n: Node = root.find_child(node_name, true, false)
	if n == null:
		push_warning("[%s] 必須ノードが見つからない: %s" % [owner_tag, node_name])
	return n
