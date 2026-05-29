class_name StationData
extends Resource

# 駅の名前・色・装飾・配置を定義する Resource。
# 6 駅それぞれ .tres ファイルとして resources/station_data/ に置く。
# 新駅追加は .tres を 1 つ作るだけ、コード変更不要(TrainData と同じデータ駆動)。

# 駅名(ひらがな、看板の大文字)
@export var display_name: String = ""

# サブテキスト(ひらがな、看板の小文字。例「もりの えき」)
@export var sub_text: String = ""

# 内部識別子(英数字、デバッグ用)
@export var slug: String = ""

# 駅舎・屋根のメインカラー
@export var main_color: Color = Color.WHITE

# 柱・縁取りのアクセント色
@export var accent_color: Color = Color(0.95, 0.95, 0.95)

# 固有装飾: "tree" / "flower" / "mountain" / "lake" / "sweets" / "rainbow"
@export var decor_type: String = "tree"

# 楕円トラック上の配置位置(0..TAU)。6 駅で重ならないよう分散
@export var track_t: float = 0.0
