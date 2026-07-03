---
name: godot-check
description: GDScript の構文チェックとシーン起動検証。.gd を変更したらコミット前に必ず実行する。構文 → Main 起動(配線・実行時エラー)の 2 段階。
---

# godot-check — コミット前の検証

Godot 実行ファイル: `C:/Users/papa/Desktop/Godot_v4.6.3-stable_win64.exe`
(Downloads にも同名フォルダがあるが、改善さんが普段使うのは Desktop の方。バージョンアップ時はこのパスを更新する)

## 1. 構文チェック(GPU 不要・速い)

変更した .gd それぞれに対して:

```bash
"C:/Users/papa/Desktop/Godot_v4.6.3-stable_win64.exe" --headless --check-only --script scripts/xxx.gd
```

終了コード 0 かつ診断行なしなら OK。複数ファイルはループで回す。

## 2. シーン起動検証(NodePath・signal 配線・_ready のエラー検出)

```bash
"C:/Users/papa/Desktop/Godot_v4.6.3-stable_win64.exe" --headless --path "C:/Users/papa/Desktop/shinkansen-world-godot" --quit-after 240
```

240 フレーム(約 4 秒)走らせて終了。出力を `ERROR` / `has_signal` / `nonexistent` / `null instance` で grep する。終了時の "ObjectDB instances leaked" 警告は無害。

## 注意

- `--headless` は GPU なしなので**シェーダーのコンパイルエラーは検出できない**。シェーダー・見た目の変更は `godot-screenshot` スキル(AutoCapture・実 GPU)で必ず確認する。
- `--headless --editor` は使わない(`export_presets.cfg` を勝手に書き換える)。
- Godot 実行で `export/web/` が汚れることがある。コミット前に `git status` を確認し、意図しない差分は `git checkout -- export/web` で戻す。
