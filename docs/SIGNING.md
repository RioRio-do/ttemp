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

## 自動更新（Sparkle 2）

Sparkle 2 を SPM で組み込み済み。Apple Developer ID は使わず、更新パッケージの
検証は Sparkle の EdDSA 鍵で行う。

構成:

- 秘密鍵: `generate_keys` が作り、ログインキーチェーンに入っている
  （別マシンでリリースするには鍵のエクスポートが必要。`generate_keys -x` 参照）
- 公開鍵: `Sources/App/Info.plist` の `SUPublicEDKey`
- フィード: `SUFeedURL` = `https://raw.githubusercontent.com/RioRio-do/ttemp/main/appcast.xml`
  （リポジトリ直下の appcast.xml を main に push すると配信される）
- 挙動: 自動チェック ON（`SUEnableAutomaticChecks`）、確認なしの自動ダウンロード・
  インストール（`SUAutomaticallyUpdate`）。手動確認はメニューバーの「最新版を確認…」

リリース手順:

1. `project.yml` の `MARKETING_VERSION`（表示用）と `CURRENT_PROJECT_VERSION`
   （更新判定に使う整数。**リリースごとに必ず上げる**）を上げる
2. `./scripts/build-release.sh`
   （ビルド → 安定署名 → `dist/Ttemp.zip` → EdDSA 署名つき appcast.xml 生成）
3. `appcast.xml` をコミットして push
4. `gh release create "v<版>" dist/Ttemp.zip`

順序に注意: appcast を push するのはリリース（zip の公開）後でもよいが、
逆にすると数分間「appcast にはあるのにダウンロードできない」状態になる。
Sparkle が入れ替えたアプリは quarantine が付かないので、更新に Gatekeeper の
回避は不要（初回の手動インストールだけ従来どおり）。
