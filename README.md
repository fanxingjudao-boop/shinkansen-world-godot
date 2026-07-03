# しんかんせんワールド (Godot 4 版)

iPad で遊ぶ、3〜7 歳児向けの新幹線オープンワールドゲーム。

## プロジェクトの状態

**運用中(v0.58 台)** — Vercel で配信中: https://shinkansen-world-godot.vercel.app/

Three.js プロトタイプ(`reference/threejs-prototype/`)を Godot 4 で本格的に作り直し、
電車(乗る・運転・分岐)、6 つの別世界+銀河鉄道、図鑑・ミッション・ごほうび、
主人公えらび(うんてんしさん/きつね)まで実装済み。履歴は `changelog.md` 参照。

## 何を作っているか

- 新幹線が走るオープンワールド
- 主人公が散歩して、お星さま集め・動物との出会い・電車図鑑コンプリート・駅巡りを楽しむ
- 3〜7 歳児向け、優しい世界観(失敗・敵・時間制限なし)
- iPad の Safari で PWA として動作

## 技術スタック

- **エンジン**: Godot 4.6(最新安定版に追従)
- **言語**: GDScript
- **レンダラー**: Compatibility(Web Export 用)
- **配信**: Web Export → PWA
- **ホスティング**: Vercel(GitHub 連携で push 時に自動デプロイ)
- **開発環境**: Windows 11

## 開発

このプロジェクトの作業は **Claude Code** に任せています。
詳細は以下のドキュメントを参照:

- `CLAUDE.md` — Claude Code への作業指示書(必読)
- `docs/HANDOFF.md` — 現在地・恒久ルール・設計判断の経緯
- `docs/ARCHITECTURE.md` — シーン構造とコード設計
- `docs/ROADMAP.md` / `docs/PLAYFUL_DETAILS.md` — 開発計画・遊び心のアイデア集
- `docs/GODOT_NOTES.md` — Godot 4 固有の技術メモ
- `docs/GAME_OVERVIEW.html` — 現在の機能の全体像(ブラウザで開く)

## ローカルでの Web 動作確認

```bash
cd export/web
python -m http.server 8000
# → http://localhost:8000 で確認(キャッシュが残るときはポートを変える)
```

## 開発フロー

1. `docs/HANDOFF.md` の「▶ 現在地」から作業を再開
2. 検証は `.claude/skills/` のスキルで: **godot-check**(構文+起動)→ **godot-screenshot**(見た目)→ **web-export**(デプロイ)
3. 変更は改善さんに確認、changelog.md と HANDOFF の現在地を更新
4. push は改善さんが `! git push origin main`(Vercel が自動デプロイ)

## ライセンス

身内利用のため、ライセンス明記なし。

## 注意

このプロジェクトは Claude.ai での設計、Claude Code での実装、改善さんの運用、という体制で進めています。
