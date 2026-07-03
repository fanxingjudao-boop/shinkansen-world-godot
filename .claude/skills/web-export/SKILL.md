---
name: web-export
description: Web 版の再エクスポート〜デプロイの正規手順。ゲーム挙動または UI を変えるコミットの後に実行する(コード掃除など挙動不変の変更では不要)。
---

# web-export — Web 再エクスポートとデプロイ

ライブ(Vercel)に反映する正規手順。**push はこの環境ではブロックされる**ので、最後の push は改善さんに `! git push origin main` を依頼する(Vercel が自動デプロイ)。

## 手順

1. **ソースのコミットを先に済ませる**。その際 `export/web` に意図しない差分があれば `git checkout -- export/web` で戻す(Godot 実行で勝手に汚れるため。AutoCapture 実行でも index.* が debug ビルドに化けることがある)。
2. **エクスポート**(正規反映は必ずこの CLI 出力を使う):
   ```bash
   "C:/Users/papa/Desktop/Godot_v4.6.3-stable_win64.exe" --headless --path "C:/Users/papa/Desktop/shinkansen-world-godot" --export-release "Web" export/web/index.html
   ```
3. **検証**:
   - `git diff export_presets.cfg` が空(非破壊。`for_mobile=false`・`custom_html_shell=res://web/template.html` 維持)
   - `export/web/` のファイル名が `index.*` の正規名(日本語ファイル名に化けていない)
   - `web/template.html` 由来の noindex meta と `export/web/robots.txt`(Disallow: /)が維持されている
   - release サイズ目安: index.wasm ≈ 37.7MB(debug 35.7MB に化けていたら手順 2 をやり直す)
4. **コミット**: `git add -u export/web` → コミット(差分は実質 `index.html` + `index.pck` のみのはず)。
5. **push 依頼**: 改善さんに `! git push origin main` を依頼。
6. **push 後のライブ確認**(CLAUDE.md セキュリティ原則):
   1. ゲームが起動する
   2. 文字が出る
   3. 外部通信が増えていない(開発者ツールのネットワークタブ)

## 落とし穴(過去に実際にハマったもの)

- Godot エディタで Project > Export を開くと `export_presets.cfg` が正規化・上書きされることがある。CLI エクスポートを正とする。
- `--headless --editor` は使わない(同じく presets を書き換える)。
- Compatibility + Web では `ProceduralSky` が描画されない(背景単色 + ambient Color で回避済み)。空まわりを触ったら Web 実機で確認する。
