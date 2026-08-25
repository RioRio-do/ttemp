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

自己署名のため、macOSに止められた場合はApplications内のTtempを右クリックして「開く」。

## 入力監視

左右Shiftの判定だけに使います。入力監視で得たイベントは保存・送信しません。
ノートは端末内にのみ保存されます。許可しなくてもメニューバーから使えます。

## 必要環境

- macOS 14以降
- ビルド: Xcode、[XcodeGen](https://github.com/yonaskolb/XcodeGen)

## ビルド

```bash
xcodegen generate
xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -configuration Release build
```

## リリース

mainへのpushで、CIがテスト、署名、DMG/ZIP/appcast生成、GitHub Release作成まで行います。
鍵の準備と検証手順は[docs/SIGNING.md](docs/SIGNING.md)を参照してください。

## ドキュメント

- [SPEC.md](SPEC.md) — 仕様
- [docs/SIGNING.md](docs/SIGNING.md) — 署名・更新・リリース

## ライセンス

[MIT-0](LICENSE)
