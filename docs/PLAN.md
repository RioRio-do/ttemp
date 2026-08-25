# Ttemp 実装計画

仕様は [SPEC.md](SPEC.md) を参照。本書は**実装の進め方・構成・技術的な注意点**をまとめたもの。

---

## 1. 進め方

**段階的に実装し、各フェーズの終わりにユーザーが実機で確認する。**

フェーズ1の時点で「左右 Shift の誤爆頻度」「空ウィンドウの自動消滅が鬱陶しくないか」という、**体感でしか判断できない核心部分**が検証できる。ここが気に入らなければ後続の設計も変わるため、一気に全部作ってから確認する方式は採らない。

### フェーズ1: 骨格

**ゴール**: 左右 Shift でウィンドウが出て、書いて、閉じるとクリップボードに入る。

- [x] XcodeGen プロジェクトの雛形（`project.yml`、Info.plist、Hardened Runtime 有効化）
- [x] `.accessory` ポリシーでの起動、`NSStatusItem` 常駐（アイコン `t.square`）
- [x] `CGEventTap` によるキー・マウス監視と入力監視権限の取得フロー
- [x] 左右 Shift 判定ステートマシン（**純粋ロジックとして分離し、ここで XCTest を書く**）
- [x] ウィンドウ生成（透明タイトルバー、閉じるボタンのみ、480×320、中央やや上、カスケード）
- [x] **生成時に `NSApp.activate` してキーウィンドウにする**（SPEC §3.1）
- [x] `NSTextView` のセットアップ（プレーンテキスト、自動処理全 OFF、Tab、フォント14pt）
- [x] 空ウィンドウのフォーカスアウト自動消滅（**ピン留め中は除外**。フェーズ4でピン留めを実装するまでは条件だけ用意）
- [x] 閉じる（閉じるボタン / `⌘W` / `Escape`）＋クリップボードコピー
- [x] 閉じたとき、記憶しておいた直前のアプリへフォーカスを戻す（SPEC §4。アクティブ化する直前に `NSWorkspace.frontmostApplication` を記憶しておく）
- [x] メニューバー左クリックで全ウィンドウ前面、右クリックで最小限のメニュー（新規ウィンドウ / 終了）
- [x] フェードイン・フェードアウト

フェーズ1で先取りした項目: `PlainTextSanitizer`（ペースト時の改行正規化、SPEC §5.3）と mainMenu の
`⌘F` / `⌘⌥F` 配線。find bar 表示中の Escape の扱いはフェーズ4に残している（`NoteTextView` に TODO）。

**この時点で確認してもらうこと**: 誤爆しないか、出現位置は使いやすいか、空ウィンドウの消滅タイミングは自然か、**他アプリがフロントの状態から呼び出して確実にキー入力できるか**（協調的アクティベーション、§3.10）。

### フェーズ2: 永続化

**ゴール**: アプリを終了しても内容と配置が戻る。

- [x] 状態モデルの定義と Codable 実装（**XCTest を書く**）
- [x] `~/Library/Application Support/Ttemp/state.json` へのアトミック書き込み
- [x] 設定値は `UserDefaults` に分離（SPEC §10.2）
- [x] 1秒デバウンスの逐次保存＋Quit 時保存
- [x] 起動時の復元（非アクティブのまま表示）
- [x] **復元位置の可視領域クランプ**（**XCTest を書く**。ディスプレイ構成が変わっても画面外に出さない）
- [x] 破損ファイルの `.corrupt-<日時>` リネーム処理
- [x] `SMAppService` によるログイン時起動

### フェーズ3: 画像モード

**ゴール**: 画像を貼れる。

- [x] ペースト内容の判定（画像データ → ファイル URL → テキストの優先順）（**XCTest を書く**）
- [x] 画像モードへの遷移と拒否フィードバック（シェイク）
- [x] 画像モード中のテキストペースト拒否、複数ファイルドロップ時は先頭の画像のみ受付
- [x] 画像ウィンドウは「空」扱いにしない（自動消滅の対象外）
- [x] 画像表示ビュー（アスペクト比維持フィット、レターボックス、ダウンサンプリング、原本保持）
- [x] ウィンドウの自動リサイズ（60%上限 / 200×150下限）
- [x] ドラッグ&ドロップ受付
- [x] GIF のホバー時のみ再生
- [x] 画像モードの右クリックメニュー（コピー / 保存サブメニュー / 削除）
- [x] `NSSavePanel` での保存（元形式 + PNG/JPEG/HEIC/TIFF、前回保存先の記憶）
- [x] 画像の永続化（原本バイト列を個別ファイルとして保存）

### フェーズ4: 仕上げ

**ゴール**: 全機能が揃う。

- [x] 文字サイズモデル（グローバル値＋オフセット、クランプ）（**XCTest を書く**）
- [x] キーボードショートカット（`⌘;` 系 / `⌃;` 系 / `⌘0` / `⌃0`）
- [x] `⌘ + スクロール` / `⌃ + スクロール`
- [x] 最前面固定トグルとピンアイコン表示（**ピン留め中は空でも自動消滅しない**）
- [x] 検索・置換（`⌘F` / `⌘⌥F`）
- [x] テキストモードの右クリックメニュー（標準サブメニューの削除）
- [x] メニューバー右クリックのウィンドウ一覧（先頭30文字 / 画像サムネイル）
      ※ 前面化の導線がないと使えないため、フェーズ1で先取り実装。画像サムネイルはフェーズ3で追加
- [x] 設定画面（4項目）
- [x] オンボーディング画面
- [x] 権限剥奪時の警告表示と自動復帰

### フェーズ5: 配布準備

- [ ] 暫定アプリアイコンの作成
- [ ] entitlements の整理
- [ ] Developer ID 署名＋公証スクリプト
- [ ] `.dmg` 作成スクリプト

---

## 2. ディレクトリ構成

```
ttemp/
├── project.yml                     # XcodeGen 定義
├── docs/
│   ├── SPEC.md
│   └── PLAN.md
├── Sources/
│   ├── App/
│   │   ├── main.swift              # NSApplication のエントリポイント
│   │   ├── AppDelegate.swift       # ライフサイクル、多重起動検知、復元
│   │   ├── MainMenuBuilder.swift   # mainMenu（これがないと ⌘V すら効かない）
│   │   ├── WindowManager.swift     # 全ウィンドウの生成・破棄・一覧・前面化・スナップショット
│   │   └── Info.plist              # LSUIElement = true
│   ├── Hotkey/
│   │   ├── ShiftChordDetector.swift    # 純粋ステートマシン（テスト対象）
│   │   ├── EventTapController.swift    # CGEventTap のライフサイクル管理
│   │   └── PermissionMonitor.swift     # 入力監視権限の状態監視
│   ├── Note/
│   │   ├── NoteWindowController.swift  # 1ウィンドウ＝1インスタンス
│   │   ├── NoteWindow.swift            # NSWindow サブクラス（外観、シェイク、ショートカット）
│   │   ├── NoteTextView.swift          # NSTextView サブクラス（ペースト、D&D、メニュー）
│   │   ├── NoteImageView.swift         # 画像表示、GIFホバー再生、D&D
│   │   └── WindowPlacement.swift       # 出現位置・カスケード・復元クランプ（テスト対象）
│   ├── Model/
│   │   ├── NoteContent.swift           # .text(String) / .image(ImageReference)
│   │   ├── AppState.swift              # 永続化されるルート状態（Codable）
│   │   └── StateStore.swift            # 保存・読込・デバウンス・破損処理（テスト対象）
│   ├── StatusItem/
│   │   └── StatusItemController.swift  # 左右クリック分岐、ウィンドウ一覧メニュー
│   ├── Settings/
│   │   ├── LocalModifier.swift         # Control / Option（テスト対象）
│   │   ├── Preferences.swift           # UserDefaults ラッパ、SMAppService
│   │   └── SettingsWindowController.swift
│   ├── Onboarding/
│   │   └── OnboardingWindowController.swift
│   └── Util/
│       ├── PlainTextSanitizer.swift    # 書式剥がし（テスト対象）
│       ├── FontSizeModel.swift         # グローバル値＋オフセット（テスト対象）
│       ├── FontSizeShortcut.swift      # キー／スクロールの判定（テスト対象）
│       ├── PasteboardReader.swift      # ペースト内容の判定とモード遷移（テスト対象）
│       ├── ImageWindowSizing.swift     # 画像ウィンドウのサイズ計算（テスト対象）
│       ├── ImageExporter.swift         # 保存形式とファイル名（テスト対象）
│       └── ImageStore.swift            # 画像の保存・読込・ダウンサンプリング
└── Tests/
    └── TtempTests/                     # SPEC §13: 純粋ロジックのみ（89件）
        ├── ShiftChordDetectorTests.swift
        ├── PlainTextSanitizerTests.swift
        ├── PasteboardReaderTests.swift
        ├── FontSizeModelTests.swift
        ├── WindowPlacementTests.swift
        ├── RestoredFrameTests.swift
        ├── ImageSizingTests.swift
        └── StateStoreTests.swift
```

---

## 3. 技術メモ（実装前に把握しておくべき事項）

### 3.1 `.accessory` ポリシーとキーボードショートカット

`LSUIElement = true` のアプリは画面上部のメニューバーに自前のメニューを表示しない。しかし **`NSApp.mainMenu` を設定しておけば、メニューが表示されていなくてもキーイベントは `performKeyEquivalent` を通る。**

`⌘C` / `⌘V` / `⌘X` / `⌘A` / `⌘Z` / `⌘W` / `⌘F` を機能させるには、**Edit メニューを含む `mainMenu` を必ず組み立てておくこと。** これを怠ると `NSTextView` の基本的な編集ショートカットが一切効かない。

### 3.2 `CGEventTap`

```swift
CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,          // 読み取り専用。イベントを消費しない
    eventsOfInterest: CGEventMask((1 << CGEventType.keyDown.rawValue) |
                                  (1 << CGEventType.flagsChanged.rawValue) |
                                  (1 << CGEventType.leftMouseDown.rawValue) |
                                  (1 << CGEventType.rightMouseDown.rawValue) |
                                  (1 << CGEventType.otherMouseDown.rawValue)),
    callback: ...,
    userInfo: ...
)
```

- **マウスの `*MouseDown` を含めること。** SPEC §2 で「両 Shift 押下中にマウスボタンが押されたら無効」と決めているため
- **`.listenOnly` を使うこと。** イベントを書き換えないので他アプリの入力を妨げない
- **`tapDisabledByTimeout` / `tapDisabledByUserInput` を必ずハンドルする。** システムはタップが重いと判断すると勝手に無効化するため、これらのイベントを受けたら `CGEvent.tapEnable(tap:enable:true)` で再有効化する。これを忘れると「ある日突然ホットキーが効かなくなる」
- 権限チェックは `CGPreflightListenEventAccess()`、要求は `CGRequestListenEventAccess()`

### 3.3 左右 Shift の判別

`CGEventFlags` の `.maskShift` は左右を区別しない。区別するには2通り。

- **`flagsChanged` イベントの `keyCode`**: 左 Shift = `56`、右 Shift = `60`
- **`flags` の raw value のデバイス依存ビット**: 左 = `0x00000002`、右 = `0x00000004`

**後者（デバイス依存ビット）を主に使うのが堅牢。** `flagsChanged` を受けるたびに現在の左右押下状態を直接読めるため、押下順やイベント欠落に影響されない。`keyCode` 方式は down/up の対応付けを自前で管理する必要がある。

**CapsLock / Fn は「状態」ではなく「打鍵」で判定すること。** CapsLock のロック状態は `maskAlphaShift` として flags に立ち続けるため、「flags に他の修飾ビットが立っていたら無効」と実装すると CapsLock 常用環境では永久に発火しない。無効条件は `flagsChanged` の変化（該当キーが押されたこと）で見る（SPEC §2）。

### 3.4 `NSTextView` のプレーンテキスト強制

```swift
textView.isRichText = false
textView.importsGraphics = false
textView.isAutomaticQuoteSubstitutionEnabled = false
textView.isAutomaticDashSubstitutionEnabled = false
textView.isAutomaticTextReplacementEnabled = false
textView.isAutomaticSpellingCorrectionEnabled = false
textView.isAutomaticLinkDetectionEnabled = false      // ← 必須。切らないと入力したURLに自動でリンク属性が付く
textView.isAutomaticDataDetectionEnabled = false      // 日付・住所等の自動リンク化
textView.isContinuousSpellCheckingEnabled = false
textView.isGrammarCheckingEnabled = false
textView.usesFindBar = true
textView.isIncrementalSearchingEnabled = true
```

- **`isAutomaticLinkDetectionEnabled = false` を忘れないこと。** SPEC §5.3 でペースト時にリンク属性を削除すると決めているが、これを切らないと**入力側で URL を打った瞬間にリンク属性が付与され**、同じルールが破られる
- **「自動大文字化」に対応する `NSTextView` のプロパティは存在しない可能性が高い**（`isAutomaticCapitalizationEnabled` は UIKit 側の API と混同しやすい）。実装時に実在を確認し、無ければ `enabledTextCheckingTypes` から該当ビットを外す形で対処する
- **`isRichText = false` だけでは不十分。** ペーストの制御は `paste(_:)` をオーバーライドして自前で処理する（SPEC §5.4 の判定順を実装する必要があるため、どのみち自前処理になる）

### 3.5 `NSWindow` の設定

```swift
styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
titlebarAppearsTransparent = true
titleVisibility = .hidden
isMovableByWindowBackground = true
standardWindowButton(.miniaturizeButton)?.isEnabled = false
standardWindowButton(.zoomButton)?.isEnabled = false
level = isPinned ? .floating : .normal
// collectionBehavior に .canJoinAllSpaces を付けない（Space 固定のため）
```

- ピンアイコンはタイトルバー領域に `NSTitlebarAccessoryViewController`（`layoutAttribute = .right`）で追加するのが素直
- Escape の処理は `NSWindow.cancelOperation(_:)` または `NSTextView.cancelOperation(_:)` で受ける。**`textView.hasMarkedText()` が true の間は IME に委ねて閉じない**

### 3.6 `NSStatusItem` の左右クリック分岐

`statusItem.menu` を設定すると**左クリックでもメニューが開いてしまう**ため、`menu` は `nil` のままにする。

```swift
button.sendAction(on: [.leftMouseUp, .rightMouseUp])
button.action = #selector(handleClick)
// handleClick 内で NSApp.currentEvent?.type を見て分岐し、
// 右クリック時のみ statusItem.menu = menu; button.performClick(nil); statusItem.menu = nil
```

### 3.7 画像の原本保持

`NSPasteboard` から `NSImage` として読むと**元のバイト列と形式情報が失われる**（「元の形式のまま保存」ができなくなる）。

`pasteboard.data(forType:)` で**生データを取得して保持し、表示用に別途 `NSImage` を生成する**こと。ファイル URL 経由の場合も同様にファイルのバイト列をそのまま読む。

### 3.8 GIF のホバー再生

`NSImageView.animates` を `NSTrackingArea`（`.mouseEnteredAndExited`）で切り替える。静止時は `animates = false` で1枚目が表示される。

### 3.9 状態の保存

```swift
try data.write(to: url, options: .atomic)
```

`.atomic` は一時ファイルに書いてから rename するため、書き込み中のクラッシュでファイルが壊れない。

画像は `state.json` に埋め込まず、`Images/<uuid>.<ext>` として個別ファイルに保存する（JSON が肥大化して逐次保存が重くなるのを避けるため）。

### 3.10 macOS 14 の協調的アクティベーション

macOS 14 (Sonoma) 以降、`NSApp.activate()` は協調的モデルに変わり、フロントのアプリからの譲渡(yield)が無い場合は活性化要求が無視されることがある。本アプリの「他アプリで作業中に CGEventTap 起動でフォーカスを取る」は正にこの制限に当たりやすいパターン。フェーズ1の実機確認で「ウィンドウは出るがキー入力が他アプリに流れる」症状が出た場合は、非推奨だが従来挙動の `NSApp.activate(ignoringOtherApps: true)` に切り替える。

### 3.11 多重起動の検知

`NSRunningApplication.runningApplications(withBundleIdentifier:)` で自分以外の同一 Bundle ID を探す。見つかったら `DistributedNotificationCenter` で「全ウィンドウを前面に」を通知し、自身は即 `NSApp.terminate(nil)`。

---

## 4. 実装上の落とし穴チェックリスト

実装中に見落としやすい点。フェーズ1〜4の実装ではすべて対処済み。

- [x] `mainMenu` を組まないと `⌘V` すら効かない（§3.1）
- [x] `tapDisabledByTimeout` を無視するとホットキーが突然死ぬ（§3.2）
- [x] `isAutomaticLinkDetectionEnabled` を切らないと入力した URL にリンク属性が付く（§3.4）
- [x] `NSImage` 経由で画像を持つと元形式が失われる（§3.7）
- [x] `statusItem.menu` を設定すると左クリック分岐ができない（§3.6）
- [x] IME 変換中の `Escape` でウィンドウを閉じてはいけない（§3.5）
- [x] 空ウィンドウを閉じるときにクリップボードを空文字で上書きしない（SPEC §4）
- [x] Quit 時・フォーカスアウト時にクリップボードへコピーしない（SPEC §4）
- [x] 文字サイズのクランプは**表示時のみ**。オフセット値自体は保持する（SPEC §7.1）
- [x] 画像を削除してもウィンドウサイズは戻さない（SPEC §6.2）
- [x] **新規生成時はアクティブ化する / 復元時はアクティブ化しない**（SPEC §3.1・§10.3）
- [x] **画像ウィンドウとピン留めウィンドウは自動消滅の対象外**（SPEC §3.2）
- [x] **復元位置を可視領域にクランプしないと、ディスプレイを外した時にウィンドウが操作不能になる**（SPEC §10.3）
- [x] **CapsLock のロック状態を無効条件にすると CapsLock 常用環境で発火しなくなる**（§3.3。判定は打鍵で行う）
- [x] **macOS 14 の協調的アクティベーションで `NSApp.activate()` が無視されることがある**（§3.10）
- [x] **ペースト判定はファイル URL を最優先**。Finder のコピーはアイコン画像を pasteboard に載せることがある（SPEC §5.4）
