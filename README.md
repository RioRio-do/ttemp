# Ttemp

[English](README.en.md)

左右 Shift で、一時メモ。

- 閉じるとクリップボードへコピー
- テキストと画像に対応
- 再起動後も復元
- 日本語 / English

## インストール

[Ttemp.dmgをダウンロード](https://github.com/RioRio-do/ttemp/releases/latest/download/Ttemp.dmg)し、
TtempをApplicationsへドラッグする。

Ttempは自己署名で未公証です。公式GitHub Releaseからのみ入手してください。
初回起動が止められた場合は、[Appleの案内](https://support.apple.com/ja-jp/102445)に従い「システム設定 → プライバシーとセキュリティ → このまま開く」。

## 入力監視

左右Shiftの判定だけに使います。入力監視で得たイベントは保存・送信しません。
ノートは端末内にのみ保存されます。許可しなくてもメニューバーから使えます。

## 必要環境

- macOS 14以降（Apple Silicon / Intel）
- ビルド: Xcode、[XcodeGen](https://github.com/yonaskolb/XcodeGen)

## ビルド

```bash
xcodegen generate
xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -configuration Debug build
```

配布版の検証（使い捨て鍵・隔離データ）: `./scripts/test-release.sh`

## リリース

mainへのpushで、CIがテスト、署名、DMG/ZIP/appcast生成、GitHub Release作成まで行います。
変更と一緒に[短い日英リリースノート](release-notes/README.md)を追加してください。ノートなしの公開は停止します。
鍵の準備と検証手順は[docs/SIGNING.md](docs/SIGNING.md)を参照してください。

## ドキュメント

- [SPEC.md](SPEC.md) — 仕様
- [docs/SIGNING.md](docs/SIGNING.md) — 署名・更新・リリース
- [SECURITY.md](SECURITY.md) — 脆弱性の非公開報告

## ライセンス

[MIT-0](LICENSE)
