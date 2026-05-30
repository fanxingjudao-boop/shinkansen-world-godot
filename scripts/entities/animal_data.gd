class_name AnimalData
extends Resource

# 動物の名前・見た目・種類を定義する Resource。
# 8 種それぞれ .tres ファイルとして resources/animal_data/ に置く。
# 新しい動物の追加は .tres を 1 つ作るだけ(TrainData / StationData と同じデータ駆動)。

# 名前(ひらがな、なかよし通知・図鑑用)
@export var display_name: String = ""

# 内部識別子(英数字)
@export var slug: String = ""

# 見た目の種類: "rabbit" / "bear" / "fox" / "cat" / "panda" / "dog" / "penguin" / "pig"
@export var species: String = "rabbit"

# 体のメインカラー
@export var body_color: Color = Color.WHITE

# 耳・しっぽなどのアクセント色
@export var accent_color: Color = Color(0.9, 0.9, 0.9)

# おなか・顔まわりの色
@export var belly_color: Color = Color(1.0, 1.0, 1.0)

# 全体の大きさ倍率(くまは大きめ、ねこは小さめ等)
@export var scale_factor: float = 1.0
