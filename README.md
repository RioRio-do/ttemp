# Ttemp

左右の Shift キーを同時に押すと、どこからでも一時メモが開く macOS メニューバー常駐アプリ。

Press both Shift keys to open a scratch note from anywhere. A tiny macOS menu bar app.

- 閉じると内容は自動でクリップボードへ（Close a note and its content lands on the clipboard）
- プレーンテキストと画像のみ、装飾なし（Plain text and images only）
- 日本語 / English（設定または初回起動時に選択）

## 必要環境

- macOS 14.0 以降
- ビルドには Xcode と [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## ビルド

```bash
xcodegen generate
xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -configuration Release build
```

## リリース

main へ push するだけ。CI（GitHub Actions）がテスト → バージョン採番 →
署名 → GitHub Release 作成まで全自動で行う。鍵のセットアップ（一度だけ）や
仕組みの詳細は [docs/SIGNING.md](docs/SIGNING.md) を参照。

## テスト

```bash
xcodebuild -project Ttemp.xcodeproj -scheme TtempTests -destination 'platform=macOS' test
```

## 権限について

左右 Shift の同時押し検知に macOS の「入力監視」権限を使う。キー押下の検知のみで、
入力内容の記録・送信は一切しない。許可しなくても、メニューバーアイコンから
「新規ウィンドウ」で使える。

## ドキュメント

- [SPEC.md](SPEC.md) — 仕様（このアプリの唯一の仕様書。コードのコメントは §番号で参照する）
- [docs/SIGNING.md](docs/SIGNING.md) — 自己署名による安定署名、Sparkle 2 の自動更新とリリース手順
