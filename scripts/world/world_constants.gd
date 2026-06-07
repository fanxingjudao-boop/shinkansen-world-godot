extends RefCounted

# 別世界スクリプト(moon_trip / sky_castle / submarine / candy_land / dino_land /
# yuki_land / ginga_railway)で「完全に同じ値」になっている定数の単一情報源。
#
# 今回(掃除)は値が一致しているものだけを集約する。値がバラついている
# ENTER_RANGE(8.5〜10.0)やアイテム取得距離(2.8〜4.0)は、統一すると
# 挙動が変わってしまうため ここには入れない(③ BaseWorld 抽出 or 実機調整時に検討)。
#
# 使い方(preload。class_name は新規だと --check-only で未登録になりうるため使わない):
#   const WorldConstants = preload("res://scripts/world/world_constants.gd")
#   const FADE_TIME := WorldConstants.FADE_TIME

const FADE_TIME := 0.35   # ワープ時のフェード時間(7世界すべて同値)
