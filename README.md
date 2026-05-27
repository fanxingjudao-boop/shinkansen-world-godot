# しんかんせんワールド (Godot 4 版)

iPad で遊ぶ、3〜7 歳児向けの新幹線オープンワールドゲーム。

## プロジェクトの状態

**新規プロジェクト(Godot 4 + GDScript + Web Export)**

Three.js で作成したプロトタイプ(`reference/threejs-prototype/`)を、Godot 4 で本格的に作り直すフェーズに入りました。

## 何を作っているか

- 新幹線が走るオープンワールド
- 主人公が散歩して、お星さま集め・動物との出会い・電車図鑑コンプリート・駅巡りを楽しむ
- 3〜7 歳児向け、優しい世界観
- iPad の Safari で PWA として動作

## 技術スタック

- **エンジン**: Godot 4.3 以降
- **言語**: GDScript
- **レンダラー**: Compatibility(Web Export 用)
- **配信**: Web Export → PWA
- **ホスティング**: Vercel または GitHub Pages
- **開発環境**: Windows 11

## 開発

このプロジェクトの作業は **Claude Code** に任せています。
詳細は以下のドキュメントを参照:

- `CLAUDE.md` — Claude Code への作業指示書(必読)
- `docs/HANDOFF.md` — 設計判断の経緯と既知の課題
- `docs/ARCHITECTURE.md` — シーン構造とコード設計
- `docs/ROADMAP.md` — Phase 0〜7+ の開発計画
- `docs/GODOT_NOTES.md` — Godot 4 固有の技術メモ

## クイックスタート(Claude Code 向け)

```bash
# 1. Godot 4.3 以降をダウンロード(改善さん側で)
#    https://godotengine.org/download

# 2. Godot で project.godot を開く
#    まだ存在しない → Phase 0 で作成

# 3. Phase 0 から進める
#    docs/ROADMAP.md 参照

# 4. ローカルでの Web 動作確認
#    Godot で Export > Web → export/web/ に出力
cd export/web
python -m http.server 8000
# → http://localhost:8000 で確認
```

## 開発フロー

1. Phase 0 から順に実装
2. verification-agent スキル(LIGHT モード)で作業
3. 各 Phase 完了時に改善さんに確認
4. changelog.md に変更履歴を記録
5. 失敗事例は failure-log への抽象化を検討

## ライセンス

身内利用のため、ライセンス明記なし。

## 注意

このプロジェクトは Claude.ai での設計、Claude Code での実装、改善さんの運用、という体制で進めています。
