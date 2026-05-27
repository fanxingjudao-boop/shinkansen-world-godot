# Changelog

verification-agent LIGHT モードで Claude Code が変更を記録します。

## v0.3.0 — 2026-05-28 — Phase 0-5(Web Export ローカル動作確認)

- `web/template.html` を新規作成 — iPad 向け meta タグ、100dvh、パステル色のローディング画面、ひらがな表示
- `vercel.json` を新規作成 — COEP/COOP/CORP ヘッダー(Phase 0-6 のデプロイ用に先行準備)
- `export_presets.cfg` を新規作成 — Web プリセット(Threading: false、Custom HTML Shell 指定、Compatibility 想定)
- `Main.tscn` 修正 — `background_mode` を Sky(2) → Color(1) に変更し、空色 `#7ec8f5` を `background_color` に直接指定(Compatibility レンダラー + Web Export で ProceduralSky が描画されなかったため)
- `Main.tscn` 修正 — `ambient_light_source` を Sky(3) → Color(2) に変更、`ambient_light_energy` を 0.35 → 0.5 に
- `TouchHUD.tscn` 修正 — D-pad の ▲▼◀▶ ボタンの font_size を 32 → 40、「タッチ」を 22 → 28、「ジャンプ」を 20 → 26 に拡大(改善さんから「ボタン文字つぶれ」フィードバック)
- 改善さんが Godot 4.6 で Web Export Templates をダウンロード、Project > Export > Web → `export/web/index.html` に書き出し成功(初回は ファイル名が「しんかんせんワールド.*」になったため Claude Code がリネーム + HTML 内参照置換、2 回目は最初から `index` 指定で出力)
- ローカル HTTP サーバー(`python -m http.server`)で動作確認完了:操作可能・キャラ移動・ボタン入力すべて動作。背景空色とボタン文字も改善後の Export で適用済み
- 次のステップ: Phase 0-6(Vercel または GitHub Pages へのデプロイ)、その後 iPad 実機での動作確認

## v0.2.0 — 2026-05-27 — Phase 0 着手(0-1 〜 0-4)

- ルート直下の重複ドキュメントを削除(正本は `docs/` 配下に統一)
  - 削除: `ARCHITECTURE.md`, `CLAUDE-godot.md`, `GODOT_NOTES.md`, `ROADMAP-godot.md`
- `project.godot` を作成(Compatibility レンダラー、1920×1080 ビューポート、9.8 重力、空色クリアカラー `#7ec8f5`)
- `icon.svg` を新規作成(新幹線+空+太陽+雲のパステル可愛いアイコン、128×128)
- ディレクトリ構造を作成(`scenes/{entities,ui}/`、`scripts/{entities,world,ui}/`、`.gitkeep` で git 追跡)
- `scripts/main.gd`: InputMap を動的登録(WASD/矢印/Space/E/Enter)、エントリーポイント
- `scripts/entities/player.gd`: CharacterBody3D の移動・ジャンプ、ロジック層(`_compute_horizontal_velocity`, `_compute_yaw`)と Godot 操作層を分離(C# 移行配慮)
- `scripts/world/camera_rig.gd`: 三人称追従カメラ、Lerp で滑らか、ロジック層分離
- `scripts/ui/touch_hud.gd`: タッチボタン → InputMap action ブリッジ
- `scenes/entities/Player.tscn`: カプセル体 + 球頭 + 桜色の鼻、Group "player"
- `scenes/ui/TouchHUD.tscn`: 左下 D-pad(72px、空色)+ 右下ジャンプ(96px、桜色)/タッチ(96px、黄色)ボタン、StyleBoxFlat でパステル彩色、ダーク UI 不使用
- `scenes/Main.tscn`: ProceduralSky(空色〜)、太陽(DirectionalLight3D + 標準シャドウ)、120×120 草原(`#7ec850`)、Player インスタンス、CameraRig+Camera3D、UI レイヤー
- 次のステップ: Godot エディタで F5 実行して動作確認 → 改善さんに引き継ぎ → Phase 0-5(Web Export)

## v0.1.0 — 2026-05-27 — Godot 版への切り替え

- Three.js 版プロトタイプから Godot 4 版への移行を決定
- 引き継ぎ資料一式を整備(CLAUDE.md / HANDOFF.md / ARCHITECTURE.md / ROADMAP.md / GODOT_NOTES.md)
- Three.js プロトタイプを `reference/threejs-prototype/` に保管
- 次のステップ: Phase 0(Godot プロジェクト初期化)
