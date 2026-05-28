# Changelog

verification-agent LIGHT モードで Claude Code が変更を記録します。

## v0.5.0 — 2026-05-29 — Phase 1-1 + 1-3(地形 + 線路)+ 自動スクリーンショット基盤

- `scripts/world/terrain_height.gd` 新規 — `class_name TerrainHeight` 純粋関数群。`compute_height(x, z)`(Three.js heightAt 移植、山 3+湖+二重正弦波+ノイズ)、`compute_vertex_color(h)`(雪山→草原→砂の高さマッピング)
- `scripts/world/terrain.gd` 新規 — ArrayMesh で 121×121 頂点の地形メッシュを動的生成(28800 三角形)、HeightMapShape3D 201×201 サンプルで衝突(scale で実世界 400×400 に展開)、湖 CylinderMesh 配置
- `scenes/world/Terrain.tscn` 新規 — StaticBody3D + TerrainMesh + TerrainCollision + LakeMesh の最小構成、生成はスクリプト
- `scripts/world/railway.gd` 新規 — 楕円(R_X=100, R_Z=78)を 157 点で表現、レール 2 本を 1 つの ArrayMesh に統合(円柱 8 角形断面を Path に押し出し)、枕木 MultiMeshInstance3D(157 個、地形高さに追従)。`static func ellipse_point(t)` / `ellipse_tangent(t)` で Phase 2 の Train から再利用可能に
- `scenes/world/Railway.tscn` 新規 — Node3D + TrackPath (Path3D) + Rails + Ties
- `scenes/Main.tscn` 修正 — 既存平面 Ground を削除、Terrain と Railway を追加、Sun の `directional_shadow_max_distance=100` に縮小(iPad パフォーマンス)
- `scripts/main.gd` 修正 — `_settle_player_on_terrain()` で Player の Y を `TerrainHeight.compute_height(px, pz) + 1.5` に動的補正(地形のくぼみに埋まる/高山スタート事故防止)
- **自動スクリーンショット基盤**: `scripts/dev/auto_capture.gd` + `scenes/dev/AutoCapture.tscn` 新規 — Godot CLI で起動すると 2 秒待ってスクリーンショットを `user://screenshot.png` に保存して終了。視点モードを PLAYER / BIRD / SIDE で切り替え可能。これにより Claude が改善さんに F5 を依頼しなくても見た目を自動確認できるようになった

### 修正したハマりポイント(failure-log 候補)

- **ArrayMesh の三角形インデックスは反時計回り(CCW)が表面**。最初に時計回り順で `(i0, i2, i1)` と書いて地形の平地が完全に消えていた(山の斜面だけ見えた)。`(i0, i1, i2)` `(i1, i3, i2)` に修正
- **WorldEnvironment のデフォルト Filmic tonemap + 強いライト + fog 0.004 で頂点カラーが淡くなりすぎる**。`tonemap_mode=0`(Linear)、`ambient_light_energy=0.3`、`fog_density=0.002` に調整して Three.js 版に近い鮮やかさを回復

### Environment 値の変更

- `ambient_light_energy`: 0.5 → 0.3
- `tonemap_mode`: 2 (Filmic) → 0 (Linear)
- `fog_density`: 0.004 → 0.002

次のステップ: 改善さんが Web Export(ファイル名 `index` を手動入力、Custom HTML Shell を確認)→ git push で Vercel 自動再デプロイ。PC ブラウザ確認後、Phase 1-2(空・昼夜)/ 1-4(雲)/ 1-5(水)/ 1-6(桜)へ。

## v0.4.0 — 2026-05-28 — Phase 0-6(Vercel デプロイ + 本番動作確認)

- `.gitignore` 修正 — `export/` → `export/*` + `!export/web/` に変更(Git の仕様でディレクトリ全体を ignore すると配下を `!` で例外指定できないため、`export/*` 表記に切り替え)。`export/web/` 以外の `export/*`(将来の iOS/Android Export 等)は引き続き除外
- `vercel.json` 修正 — `outputDirectory: "export/web"` を追加(Vercel UI で Output Directory を手動指定する手間を省くため。Project Settings UI を一切触らず Deploy ボタンだけで完結)
- `export/web/` 配下 12 ファイルを git 管理化(`index.html/js/wasm/pck`、audio worklet 2 種、アイコン 3 種、`.import` メタ 3 種)。`index.wasm` 35.7MB(GitHub 100MB 上限内、LFS 不要)
- GitHub Public リポジトリ作成: https://github.com/fanxingjudao-boop/shinkansen-world-godot (`gh repo create --public --source=. --remote=origin --push` で一発)
- 改善さんが Vercel にサインアップ(GitHub 連携、Hobby プラン)→ `shinkansen-world-godot` をインポート → Deploy。初回の Configure Project 画面では `vercel.json` の設定が効いたため Build/Output 設定は触らず
- Vercel が `https://shinkansen-world-godot.vercel.app/` を払い出し、ステータス Ready(緑)。COEP/COOP/CORP ヘッダーと `Content-Type: application/wasm` も `vercel.json` で適用済み
- 初回アクセスで改善さんが 404 NOT_FOUND を踏んだが、Claude Code 側から WebFetch で確認したところ Vercel は `index.html` を正常返却 → エッジ伝播遅延 or ブラウザキャッシュと判断 → シークレットウィンドウで再アクセスして動作確認 OK
- PC ブラウザ(Chrome)での動作確認完了 — ローディング → ゲーム画面、Player 表示、操作可能
- iPad Safari 実機確認は保留(改善さん判断、Phase 1 と並行でいつでも実施可能。URL は変わらず)
- 次のステップ: Phase 1(ワールド構築: 地形・線路・空・水・桜)に着手

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
