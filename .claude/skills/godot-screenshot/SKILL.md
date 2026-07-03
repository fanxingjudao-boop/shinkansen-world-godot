---
name: godot-screenshot
description: AutoCapture で Godot シーンのスクリーンショットを自動撮影し、Claude が自分で見た目を確認する。シェーダー・UI・ワールドの見た目に関わる変更後に使う(改善さんに F5 を依頼する前にまずこれ)。
---

# godot-screenshot — 自動スクリーンショットによる見た目確認

`scenes/dev/AutoCapture.tscn` が Main.tscn をインスタンスし、数秒後にスクリーンショットを PNG 保存して終了する仕組み。headless では検証できないシェーダー(実 GPU)もこれで確認できる。

## 実行

```bash
"C:/Users/papa/Desktop/Godot_v4.6.3-stable_win64.exe" --path "C:/Users/papa/Desktop/shinkansen-world-godot" "res://scenes/dev/AutoCapture.tscn" 2>&1
```

数秒で Godot ウィンドウが立ち上がり、撮影して終了する。出力先:

```
C:/Users/papa/AppData/Roaming/Godot/app_userdata/しんかんせんワールド/screenshot*.png
```

(Godot は config/name をそのままフォルダ名に使うため日本語フォルダ)。この PNG を Read ツールで開いて目視確認する。

## モード切替

`scripts/dev/auto_capture.gd` の `const MODE` を書き換えてから実行する。既定は `SINGLE`(プレイヤー視点 1 枚)。機能別の `AUTO_*` モード(乗車・運転・踏切・各別世界・キャラ選択など)は同ファイルの `CaptureMode` enum とコメントを参照。カメラ視点は `VIEW` 定数(`PLAYER` / `BIRD` 俯瞰 / `SIDE` 斜め)。

## デバッグでの活用

問題切り分けのために一時編集してから撮るパターン(確認後は必ず元に戻し、コミット前に差分確認):

- fog を切る(背景同化問題の切り分け)
- `VIEW` を `BIRD` にする(全体俯瞰で配置確認。CameraRig の `_process` を止めて debug カメラに置換される)
- terrain.gd / railway.gd 側のマテリアル設定を一時変更する

## 必ず守ること

- 確認が終わったら **`MODE` を `SINGLE` に戻す**(戻し忘れをコミットしない)。
- `AUTO_*` 実行は `user://save.json` を汚すことがある(`add_star` 等)→ 確認後 **ローカルの save.json を削除**する(配信版の子のセーブは別ストレージなので無関係)。
- Godot 実行で `export/web/` が勝手に汚れることがある → コミット前に `git checkout -- export/web`。
- AutoCapture はタイトル画面を隠す。タイトルを撮るときは `auto_capture.gd` の `_ready` にある `title.visible=false` を一時的に `true` にする(確認後は必ず戻す)。
