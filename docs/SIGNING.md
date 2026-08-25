# 署名・鍵・リリース（CI/CD）

Apple Developer アカウントは使わない。リリースは main へ push するだけで
GitHub Actions（.github/workflows/ci.yml）が全自動で行う。

## 鍵は2つある

| | コード署名証明書「Ttemp Signing」 | Sparkle EdDSA 鍵 |
|---|---|---|
| 役割 | .app 本体の署名。macOS の TCC（入力監視の許可）が「同じアプリか」を判定する根拠 | 更新パッケージ（zip）とfeed（appcast）の署名。Sparkle が「本物の更新か」を検証する根拠 |
| 公開側 | 証明書（.app に埋まる） | 公開鍵（Info.plist の `SUPublicEDKey`） |
| 秘密側 | 秘密鍵（.p12 に同梱） | 秘密鍵（base64 のシード値） |
| 失うと | 許可の引き継ぎが切れる（作り直し＝全ユーザーが入力監視を再許可） | **既存ユーザーに更新を配れなくなる**（appcast の署名検証に通らない） |
| 漏れると | 「同じアプリ」を騙るバイナリを署名できる | **偽の更新を全ユーザーに配布できる**（最重要） |

どちらも「同じ鍵を使い続けること」に価値がある。だから秘密鍵を
**リポジトリにコミットしてはいけない**（公開リポジトリなら即アウト、
プライベートでも履歴に残った鍵は消せない）。リポジトリに紐づけたい場合の
正解は **GitHub Actions のリポジトリシークレット**:

- リポジトリに暗号化されて保存され、workflow 実行時にだけ復号される
- 登録後は読み出せない（write-only。ログにもマスクされる）
- コラボレータの push でも動くが、シークレットの値自体は見えない

## セットアップ（初回・鍵形式の移行時）

```bash
./scripts/setup-release-keys.sh
```

これが証明書の用意（キーチェーンへの取り込み・信頼設定込み）、Sparkle 鍵の
エクスポート、シークレット3つ（`SIGNING_CERT_P12` / `SIGNING_CERT_PASSWORD` /
`SPARKLE_ED_PRIVATE_KEY`）の登録まで行う。既存の `.p12` があれば、証明書と秘密鍵を
維持したまま macOS 15 の Security.framework でも読み込める PKCS#12 コンテナへ
再梱包し、証明書の SHA-256 fingerprint が変わっていないことを検証してから置換する。
この移行で TCC が認識する署名 identity は変わらない。
初回セットアップ後は通常再実行不要だが、旧形式の `.p12` を移行するときは再実行する。

手元の `signing/`（git 管理外）に同じものが残るので、
**パスワードマネージャ等へ必ずバックアップする**。
シークレットは読み返せないため、`signing/` を消すとバックアップが唯一の複製になる。

## リリースの流れ（全自動）

main へ push すると:

1. テストが走る（PR でも走る）
2. 通れば、バージョンを採番: `<major.minor>.<mainのコミット数>`
   - major.minor は project.yml の `MARKETING_VERSION` の先頭2要素
   - コミット数は単調増加なので、`CURRENT_PROJECT_VERSION`（Sparkle の
     更新判定に使う整数）も同じ値で自動的に増える。**手でバージョンを
     上げる作業は存在しない**。メジャー/マイナーを上げたいときだけ
     project.yml の `MARKETING_VERSION` を書き換える
3. XcodeGen 2.46.0 は公式release ZIPを固定SHA-256で検証し、Sparkle 2.9.6 は
   commit `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`へ固定してからbuild
4. 使い捨てのユーザーキーチェーンへ証明書を取り込み、user/System trust store を
   変更せず証明書 fingerprint を直接指定して安定署名し、EdDSA 署名つきZIPと
   appcast.xml、初回インストール用DMGを生成。app の code signature、DMGのchecksum・
   内部構造、ZIPとappcastのEdDSA signature、archive lengthを公開前に再検証
5. built commitと同じSHAを`--target`へ明示して`vX.Y.N`のGitHub Releaseを作成し、
   `Ttemp.dmg`、`Ttemp.zip`、`appcast.xml`、`SHA256SUMS`を添付

`Ttemp.dmg` は人が初回インストールするときの成果物。背景は言語に依存しない
`Ttemp` と矢印だけにし、左のappから右のApplicationsエイリアスへドラッグする構成にする。
`Ttemp.zip` は Sparkle の更新enclosure専用で、appcastは引き続きZIPを参照する。
`SHA256SUMS`はdownload破損やasset取り違えの確認用であり、同じ配布経路に置かれるため
publisherの独立した本人確認にはならない。

CI では headless のGUI確認を避けるため、一時キーチェーン内の秘密鍵ACLを
その job の全processへ開く。キーチェーンと復号済みファイルは Release job 専用で、
成功・失敗にかかわらず最後の cleanup step で削除する。

アプリ側の `SUFeedURL` は
`https://github.com/RioRio-do/ttemp/releases/latest/download/appcast.xml`
（常に最新リリースのアセットへリダイレクトされる固定 URL）なので、
リリースが作られた時点で配信も完了している。
`SURequireSignedFeed`と`SUVerifyUpdateBeforeExtraction`を有効にし、feedの署名と
archiveのEdDSA署名を展開前に検証する。

リリースしたくない push は、最後のコミットの**件名先頭**に `[skip release]` と書く。
本文中の同じ文字列ではスキップしない。
main の履歴を force push で書き換えるとコミット数が巻き戻り採番が壊れるので
しないこと。

## なぜ ad-hoc 署名ではだめか（安定署名の理由）

`CODE_SIGN_IDENTITY: "-"`（ad-hoc）はビルドごとに署名の同一性が変わるため、
TCC の入力監視許可が毎回リセットされる。同じ証明書で署名し続ければ
designated requirement が安定し、更新をまたいで許可が引き継がれる。
自己署名の場合の同一性判定は**証明書そのもの**に紐づくので、
証明書を作り直すと一度だけ再許可が必要になる。

開発ビルド（Xcode / xcodebuild の Debug）は ad-hoc のまま。ローカルの
開発ビルドでも安定署名したければ、project.yml の `CODE_SIGN_IDENTITY` を
`"Ttemp Signing"` にする（setup-release-keys.sh 実行後なら identity がある）。

## 別マシンへの持ち出し

CI がリリースするので、リリース目的で鍵を持ち出す必要は基本ない。
別マシンでローカル署名・手動リリースをしたい場合は `signing/` を安全な方法で
コピーして:

```bash
# コード署名証明書
security import signing/ttemp-signing.p12 -P "$(cat signing/ttemp-signing.p12.password)" -T /usr/bin/codesign
# 信頼設定（パスワード確認が出る）
# ※証明書だけ取り出すには: openssl pkcs12 -in signing/ttemp-signing.p12 -clcerts -nokeys -out /tmp/cert.pem
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/cert.pem

# Sparkle 鍵（キーチェーンに取り込む場合。build-release.sh は TTEMP_ED_KEY_FILE でファイル指定も可）
<Sparkleのbin>/generate_keys -f signing/sparkle-ed-private-key
```

手動リリースは `./scripts/build-release.sh` → 表示される `gh release create …` を実行。

## 受け取り側の注意（初回のみ）

GitHub Releaseの`Ttemp.dmg`を開き、Ttemp.appをApplicationsエイリアスへドラッグする。
Release版をDMGやDownloadsから直接起動すると、Applicationsへの配置を案内して終了する。
自己署名アプリを Web 経由で初めて入れるときは Gatekeeper にブロックされるため、
**このリポジトリの公式GitHub Releaseから入手した場合だけ**、Applications内の
Ttempを右クリック→「開く」。Developer ID署名とApple公証へ移行するまでは、macOSが
初回配布元をpublisherまで検証できない残存リスクがある。quarantine属性をcommandで
削除する手順は案内しない。
Sparkle 経由の更新には quarantine が付かないため、2回目以降は何も出ない。
