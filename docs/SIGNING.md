# 署名と配布

Apple Developer アカウントによる署名は行わない前提で、自己署名証明書による
「安定署名」を使う。

## なぜ ad-hoc 署名ではだめか

`CODE_SIGN_IDENTITY: "-"`（ad-hoc）はビルドのたびに署名の同一性が変わる。
macOS の TCC は「同じ署名要件を満たすバイナリか」で許可を引き継ぐため、
ad-hoc のままだと再ビルド・更新のたびに入力監視の許可がリセットされる。

自己署名でも **同じ証明書** で署名し続ければ designated requirement が安定し、
再ビルドしても許可はそのまま残る。

## 手順

1. 証明書を作る（初回のみ。ログインキーチェーンに `Ttemp Signing` ができる）

   ```bash
   ./scripts/create-signing-cert.sh
   ```

2. リリースビルド（署名済みの `dist/Ttemp.zip` ができる）

   ```bash
   ./scripts/build-release.sh
   ```

Xcode からの開発ビルドも安定署名にしたい場合は、`project.yml` の
`CODE_SIGN_IDENTITY: "-"` を `CODE_SIGN_IDENTITY: "Ttemp Signing"` に変えて
`xcodegen generate` し直す（証明書を作ったあとで）。

## 注意

- ad-hoc 署名のビルドから証明書署名へ切り替えた **直後の1回だけ**、
  入力監視の再許可が必要になる。以降のビルドでは引き継がれる。
- 自己署名アプリをネット経由で配ると、受け取り側では Gatekeeper に
  ブロックされる（quarantine 属性）。受け取り側は右クリック→「開く」、
  または `xattr -d com.apple.quarantine Ttemp.app` で回避する。
- 証明書の有効期間は10年。失効させたいときはキーチェーンアクセスで
  `Ttemp Signing` を削除する。

## 将来: 自動更新（Sparkle 2）

「最新版を確認…」は今のところ GitHub Releases の最新タグと比較して
リリースページへ誘導するだけ。全自動更新にするなら Sparkle 2 が候補:

- Sparkle は Apple Developer ID を要求しない。更新パッケージの検証は
  Sparkle 自身の EdDSA 鍵で行う（`generate_keys` で作る）。
- appcast.xml をどこかに公開する必要がある（GitHub Releases + raw URL や
  GitHub Pages で足りる）。
- アプリ側の署名は本ドキュメントの自己署名のままでよいが、
  「置き換え後のアプリが同じ証明書で署名されている」ことが
  TCC 許可の引き継ぎ条件になる点は変わらない。
