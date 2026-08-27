# Ttemp 仕様書

本書は Ttemp の現行実装に対する唯一の規範仕様である。コード、テスト、README、`docs/` 内の文書と本書が矛盾する場合は、意図を確認したうえで同じ変更内で両者を同期する。`docs/SPEC.md` は旧リンク向けの案内であり、独立した仕様ではない。

## 0. 適用範囲と用語

Ttemp は macOS 14 以降で動く、メニューバー常駐型の一時メモアプリである。ノートはテキストまたは画像を1枚保持し、明示的に閉じたとき内容をクリップボードへ戻す。

- 「ノート」「ウィンドウ」は、特記がなければ1枚のノートウィンドウを指す。
- 「空」はテキストモードで、前後の空白・改行を除いた本文が0文字の状態を指す。画像モードは常に空ではない。
- 「ローカル」は現在のウィンドウだけ、「グローバル」は全テキストウィンドウと今後作るウィンドウに作用する。
- 「閉じる」は閉じるボタン、`⌘W`、Escape の明示操作を指す。空ウィンドウの自動消滅やアプリ終了とは区別する。
- UI は日本語と英語を実行時に切り替えられる。仕様内で `日本語 / English` と記す場合はそれぞれの表示文言を示す。

本書の `MUST` は必須、`SHOULD` は合理的な理由がない限り守る要件を表す。

## 1. アプリケーションのライフサイクル

### 1.1 常駐方式

- `LSUIElement = true` と `.accessory` activation policy を使用し、Dock アイコンを出さない。
- メニューバー項目はプロセスの生存中、常に利用できる。
- 最後のウィンドウを閉じても終了しない。
- `⌘Q` は割り当てない。終了はステータスメニューの `終了 / Quit` から行う。
- 終了時はウィンドウを閉じる前に状態を同期保存し、内容をクリップボードへコピーしない。

### 1.2 単一インスタンス

同じ Bundle ID のプロセスが既に存在するとき、後発プロセスは分散通知 `com.am921.ttemp.bringAllToFront` を送り、既存プロセスへ全ウィンドウの前面化を依頼して終了する。

ほぼ同時の起動でも双方が終了してはならない。候補全体から、取得できる場合は最古の起動日時、同値または取得不能なら最小 PID を勝者として全プロセスが同じ判断をする。敗者は Sparkle updater やステータス項目を初期化しない。

### 1.3 ログイン時に起動

- `SMAppService.mainApp` を使用し、状態はシステムを正とする。`UserDefaults` に複製しない。
- ON: `.notRegistered` または `.notFound` は登録する。`.requiresApproval` は再登録せず Login Items 設定を開く。
- OFF: `.enabled` と `.requiresApproval` は登録解除する。未登録状態では何もしない。
- 操作失敗時はログへ記録し、設定 UI は実際のサービス状態へ戻す。

## 2. 左右 Shift ジェスチャー

### 2.1 成立条件

以下を満たす1シーケンスにつき、新規ノートを1枚開く。

1. 左右 Shift がどちらも離れている状態から、片方の Shift が押される。
2. 全 Shift が離されるまでに、左 Shift と右 Shift の両方が一度以上押下状態になる。
3. シーケンス中に通常キーの key-down がない。
4. シーケンス中に Shift 以外の修飾キー（Command、Option、Control、Caps Lock、Fn）の打鍵がない。
5. シーケンス中に左・右・その他のマウスボタン押下がない。
6. 最後に両 Shift が離される。

左右を完全に同時に押す必要はない。途中で片方を離しても、両方を一度ずつ押してから全て離せば成立する。無効入力を受けたシーケンスは、全 Shift が離されるまで再判定しない。

### 2.2 イベント監視

- `.cgSessionEventTap`、`.headInsertEventTap`、`.listenOnly` の `CGEventTap` を使う。入力イベントを変更・抑止しない。
- 監視対象は `keyDown`、`flagsChanged`、左右およびその他の `mouseDown`。
- 左右 Shift は key code 56/60 と device-dependent flag bits `0x2`/`0x4` で識別する。
- Caps Lock はロック状態ではなく `flagsChanged` の打鍵として無効入力にする。
- 発火後のウィンドウ生成はメイン run loop の次サイクルへ送る。
- timeout または user input により tap が無効化されたら再有効化し、判定状態をリセットする。
- tap の開始・停止時には detector 状態を必ずリセットし、callback 用の retained userInfo は tap を無効化してから解放する。

## 3. ノートウィンドウ

### 3.1 生成と前面化

- 左右 Shift 成立または `新規メモ / New Note` で新規ノートを作る。
- 生成時はアプリを明示的に activate し、他アプリより前へ出してキーウィンドウにし、編集ビューを first responder にする。
- 新規ウィンドウのピン状態は §9 の既定値から決める。復元ウィンドウは保存値を使う。
- 表示・未復元を合わせたノート上限は32枚。上限で新規作成を要求された場合はbeepだけで知らせ、状態を変更しない。
- ステータス項目の左クリックと多重起動通知は既存の全ウィンドウを前面へ出し、最後の1枚を key にする。ウィンドウが0枚ならフォーカスを奪わない。

### 3.2 空ウィンドウの自動消滅

テキストモードが空のまま key window でなくなったとき、0.12秒でフェードアウトしてコピーせずに閉じる。ただし次の場合は閉じない。

- sheet を表示中。
- 画像ファイルの読み込み・保存処理を受理済みで完了待ち。
- ピン留め中で、新規ウィンドウ既定が `空でも固定 / Keep if empty`。

画像モードと実質的に空でないテキストは focus-out で閉じない。自動消滅ではフォーカス復帰処理も行わない。

### 3.3 ピン留め

- ピン OFF は `.normal`、ON は `.floating` window level とする。
- ON の間はタイトルバー右端へ `pin.fill` を表示し、クリックで解除できる。
- コンテキストメニューの `最前面に固定 / Pin on Top` でも切り替える。
- ピン状態はノート単位で保存・復元する。

### 3.4 Spaces と外観

- ノートは通常ウィンドウとして全 Spaces へ強制表示しない。現在の Space で扱う。
- タイトルバーは透明、タイトル文字は非表示、close ボタンを表示する。Dock から復帰できないため miniaturize と zoom は無効にする。
- 背景は macOS の text background/text color に従い、ライト・ダーク双方で読めること。
- テキスト領域には標準の垂直スクロールを提供する。

### 3.5 閉じる導線とサイズ制約

- 閉じるボタン、`⌘W`、Escape は §4 の明示的な閉じる処理を通る。
- 最小コンテンツサイズは 200×150 pt。
- ユーザーによる移動・サイズ変更は保存対象とする。

### 3.6 初期配置と復元配置

- 新規ウィンドウの標準サイズは 480×320 pt。
- マウスポインタのある画面、なければ main screen、さらに取得不能なら 1440×900 の仮想可視領域を使う。
- 可視領域の中央から高さの8%だけ上へ置く。
- 既存ウィンドウと原点が重なるたび、右へ24 pt、下へ24 ptずらす。画面端では少しずつ開始点を変えて折り返し、最大200回で打ち切る。
- 保存 frame は最も大きく交差する現在の画面へ収める。どの画面とも交差しなければ main screen の中央へ移す。
- 復元サイズは可視領域へ収め、可能な限り 200×150 pt 以上を保つ。

### 3.7 フィードバックとフォーカス復帰

- 表示・明示終了は0.12秒のフェードを使う。
- 受理できないペースト、ドロップ、画像入出力失敗は横方向の shake で知らせる。基準位置からの offset は `[0, -8, +8, -4.8, +4.8, 0]` pt、全体0.24秒。
- 明示的に閉じるとき、Ttemp が active ならフェード開始前に「自アプリの次に前面ウィンドウを持つ他アプリ」へフォーカスを譲る。ピン留めされた他の Ttemp ウィンドウは隠さない。

## 4. 閉じるとクリップボード

空でないノートを明示的に閉じる場合、内容をクリップボードへコピーしてから閉じる。

- テキストは plain text 1表現としてコピーする。
- 画像は可能なら原本形式のバイト列と TIFF 表現を同時に載せる。
- 画像の原本も TIFF も作れない場合は、既存クリップボードを消去しない。
- 空のノートはクリップボードを変更しない。
- 同じウィンドウに対する重複した close request は1回だけ処理する。
- 空ウィンドウの自動消滅、アプリ終了、内部的な復元失敗の片付けではコピーしない。

## 5. テキストモード

### 5.1 編集

- `NSTextView` と TextKit 1 を使用する。
- Undo/Redo、Cut/Copy/Paste、Select All、`⌘F` 検索、`⌘⌥F` 置換を使えること。
- Tab はフォーカス移動ではなく `\t` を入力する。Return は改行を入力する。Escape は閉じる。
- smart quotes/dashes、automatic text replacement、data detection、自動リンク、spell correction など本文を勝手に変える機能を無効にする。
- 保存内容は属性を持たない文字列とする。
- 本文は1ノート262,144 UTF-16 code unitまで。通常入力、IME、置換、paste、復元へ同じ上限を適用し、超過する編集はshakeして拒否する。編集時は既存全文を複製せず、`NSRange`の差分長で判定する。

### 5.2 フォントとリンク

- macOS のシステムフォント（Latin は SF Pro、日本語はシステム既定）を使う。
- pasted RTF/HTML は属性を捨て、文字列だけを現在の selection へ挿入する。
- 既存 URL を通常テキストとして扱い、自動リンク属性を付けない。
- コンテキストメニューを selection 外で開いた場合は、その位置の単語を選択して標準編集操作が作用するようにする。

### 5.3 plain text 化

- pasteboard の `.string` があればその値を使う。
- `.string` がなく attributed string だけなら、その `.string` を使う。
- 改行コードは `CRLF` と `CR` を `LF` に正規化する。
- それ以外の文字内容（NULを含む）、tab、全角空白、emoji、連続空行は保持する。

### 5.4 ペースト判定の優先順位

1. file URL が1つ以上ある場合、最初の画像ファイルだけを画像候補にする。画像がなければ unsupported とし、pasteboard 上のアイコン画像へフォールバックしない。
2. file URL がなく画像データがあり、plain text 型が存在しない場合だけ画像として扱う。優先形式は GIF、PNG、JPEG、HEIC、TIFF。
3. それ以外は plain text を使う。
4. 何も取り出せなければ無操作。

画像と plain text が混在する場合はテキストを優先する。HTML の存在だけでは plain text 混在とみなさない。
優先順位が確定した時点で返し、使わない下位表現をpasteboardからmaterializeしない。上限超過のtext/image dataはunsupportedとして拒否する。

## 6. 画像モード

### 6.1 モード遷移

各ノートはテキストまたは画像1枚だけを保持する。

| 現在 | 入力 | 結果 |
| --- | --- | --- |
| 空テキスト | テキスト | selection へ挿入 |
| 非空テキスト | テキスト | selection へ挿入 |
| 画像 | テキスト | 拒否して shake |
| 空テキスト | 画像 | 画像モードへ移行 |
| 非空テキスト | 画像 | 本文を保ったまま拒否して shake |
| 画像 | 画像 | 1枚を置換 |

`画像を削除 / Remove Image` で空テキストモードへ戻す。ウィンドウサイズとノート固有の font offset は維持する。

### 6.2 表示とリサイズ

- 画像はアスペクト比を保ち、切り抜かず中央に比例縮小表示する。小さい画像を表示のために拡大しない。
- 初回貼り付け時は論理サイズ（pt）を基準に、現在画面の可視幅・高さそれぞれ60%以内へ収め、200×150 pt の下限を確保する。
- リサイズ後も元のウィンドウ中心を保ち、画面外へ出ないよう clamp する。
- 画像を置換した場合も新しい画像に合わせて再計算する。
- 復元時と画像削除時は保存済みのウィンドウサイズを維持する。

### 6.3 取り込み、コピー、保存

- ペースト、ドラッグ＆ドロップ、空テキスト時の `画像を選択… / Choose Image…` を受け付ける。
- 複数 file URL は最初の画像ファイル1枚だけを使う。非画像ファイルは拒否する。
- 原本バイト列の読み込み、形式判定、永続化は background queue で行い、メインスレッドを塞がない。
- file URLはsymbolic linkではないregular fileだけを受け付け、属性確認後も実読込byte数を再確認する。encoded dataは64 MiB以下、ImageIO frame数は100以下、全frameの累積pixel数は64,000,000以下とし、decode・保存より前に拒否する。
- ファイル拡張子より実バイトの ImageIO type を正とし、判定不能時のみ入力の拡張子ヒントを使う。
- 取り込みには世代 ID を付ける。後発の画像、文字入力、画像削除、close が先行処理を無効化し、不要となった保存済み原本を回収する。
- 画像の選択 sheet または受理済み background import 中は、見かけ上空でも focus-out 自動消滅させない。
- `⌘C` と `画像をコピー / Copy Image` は §4 と同じ原本＋TIFF コピーを行う。`⌘A` は何もしない。
- GIF は通常静止し、pointer hover 中だけ animate する。
- 保存形式は判別済みなら `元の形式 / Original`、続いて PNG、JPEG、書き出し可能な runtime だけ HEIC、TIFF。元形式は再エンコードしない。
- JPEG/HEIC 品質は0.9。変換は ImageIO source から行い、可能なメタデータと orientation を保つ。
- 既定ファイル名は `Ttemp yyyy-MM-dd HH.mm.ss.<ext>`。前回保存ディレクトリを初期値にし、成功後だけ更新する。
- 保存 panel を先に提示し、確定後の原本読み込み・変換・atomic write は background queue で行う。失敗はログと shake で知らせる。

### 6.4 原本と表示用画像

- 原本バイト列を `Images/<UUID>.<ext>` に atomic write し、表示用画像と分離する。
- 原本読み込みは可能なら memory mapping を使う。
- 単一フレーム画像で最大辺が4096 pixelを超える場合、表示用だけを4096 pixel以内へ ImageIO で downsample する。論理サイズは原本と同じにする。
- GIF/APNG/WebP など複数 frame の画像は§6.3のframe/pixel上限内に限り、animation 保持のため downsample しない。
- 上限を超える画像、ImageIOで実画像と判定できないdata、巨大静止画のdownsampleに失敗した画像はfile-backed原寸decodeへフォールバックせず拒否する。

## 7. 文字サイズ

### 7.1 モデル

- global size の既定は14 pt、保存範囲は9〜48 pt、step は1 pt。
- 各ノートは clamp しない `fontSizeOffset` を持つ。
- 表示サイズは `clamp(global + offset, 9, 48)`。
- global 変更時は全ウィンドウが offset を保ったまま追従する。
- 画像モード中も offset を保持するが、ローカル操作は効果を持たない。画像削除後に同じ相対サイズへ戻る。
- 非有限 global 値は14、非有限 offset は次回変更時に0へ正規化する。

### 7.2 操作

- Command はグローバル操作に固定する。
- 設定した Control または Option はローカル操作に使う。
- 修飾キー＋`;`、`+`、`=`、`:` は拡大、`-`、`_` は縮小、`0` はリセット。
- `⌘0` は global を14へ戻し、offset は残す。ローカル＋`0` は当該 offset を0へ戻す。
- 同じ修飾キー＋scroll でも1 ptずつ変更する。coarse wheel の閾値は3、precise delta の閾値は24。
- gesture 開始、device precision 変更、global/local scope 変更で accumulator をリセットする。momentum event は消費するがサイズを変えない。
- Command/Control/Option の余分な組み合わせは文字サイズショートカットとして扱わない。Shift は JIS の `+` 入力のため許容する。

### 7.3 ローカル修飾キー

選択肢は `Control (⌃)` と `Option (⌥)`、既定は Control。旧 `globalModifier` 値が有効なら初回読み込み時のローカル設定として互換利用する。

## 8. メニューとステータス項目

### 8.1 テキストのコンテキストメニュー

順序は Undo、Redo、separator、Cut、Copy、Paste、Select All、separator、Find、Find and Replace。空テキストだけはさらに `画像を選択… / Choose Image…` を表示する。最後に `最前面に固定 / Pin on Top` を置き、現在状態を check で示す。

### 8.2 画像のコンテキストメニュー

順序は `画像をコピー / Copy Image`、`画像を保存 / Save Image` の形式 submenu、separator、`画像を削除 / Remove Image`、separator、`最前面に固定 / Pin on Top`。

### 8.3 ステータス項目

- 通常は template SF Symbol `t.square`。入力監視未許可時は `exclamationmark.triangle` とし、`Ttemp — 入力監視が必要です / Ttemp — Input Monitoring required` を tooltip/accessibility label に使う。
- 左クリックは §3.1 の全ウィンドウ前面化。右クリックは一時的に menu を設定して表示し、直後に外して左右クリックを分岐可能に保つ。
- 右メニューの基本順序は `新規メモ / New Note`、必要時の `入力監視を許可… / Allow Input Monitoring…`、開いているウィンドウ一覧、`すべてを前面に / Bring All to Front`、`Ttemp について / About Ttemp`、`アップデートを確認… / Check for Updates…`、`GitHub`、`設定… / Settings…`、`終了 / Quit`。セクション間には separator を置く。
- 一覧のテキストタイトルは改行を空白化・前後trimした先頭30文字で、超過時は `…` を付ける。空テキストは `（空のウィンドウ） / (Empty window)`、画像は `画像 / Image`。画像 thumbnail はアスペクト比を保ち48×16 pt以内へ収める。
- 一覧が空なら一覧と Bring All を出さない。Input Monitoring 未許可でも New Note は常に出す。

### 8.4 メインメニュー

LSUIElement でも responder chain の標準キー操作を成立させるため、非表示の main menu を構築する。

- App: `Ttemp について / About Ttemp`。`⌘Q` は置かない。
- Edit: `⌘Z` Undo、`⇧⌘Z` Redo、`⌘X/C/V/A`、`⌘F` Find、`⌥⌘F` Find and Replace。
- Window: `⌘W` Close。
- 言語変更時に再構築する。
- About panel は300×210 pt。標準 panel のOS言語混在を避け、言語非依存の `Ttemp`、`<version> (<build>)`、`GitHub` だけを表示する。

## 9. 設定

設定ウィンドウは460×300 pt、title は `設定 / Settings`。初回表示だけ中央へ置き、次回以降はユーザー位置を保つ。次の6項目だけをこの順で持つ。

1. `言語 / Language`: 日本語、English。変更は開いている設定画面、main menu、以後生成する menu・alert に再起動なしで反映する。
2. `個別操作キー / Per-window key`: Control または Option。
3. `文字サイズ / Font size`: 整数の9〜48 pt。field と stepper を同期する。
4. `新規ウィンドウを固定 / Pin new windows`: `なし / Off`、`空なら閉じる / Close if empty`、`空でも固定 / Keep if empty`。既定は中央の選択肢。
5. `ログイン時に起動 / Launch at login`: §1.3 の実システム状態を表示・変更する。
6. `入力監視 / Input Monitoring`: `許可済み / Allowed` または `未許可 / Not allowed`。未許可時だけ `システム設定 / System Settings` ボタンを出す。表示中は2秒ごと、tolerance 1秒で更新する。

言語、個別操作キー、文字サイズ、固定方法の各controlには、表示言語に従う明示的なaccessibility labelを設定する。入力監視のstatus labelは項目名と状態を合わせて読み上げる。

旧 Bool `pinsNewWindowsByDefault` は true を `pinnedKeepEmpty`、false を `unpinned` として互換読み込みする。

## 10. 永続化

### 10.1 保存タイミングと I/O

- ルートは user Application Support の `Ttemp`、状態は `state.json`、画像は `Images/`。
- 本文、画像、pin、font offset、移動、resize、close による状態変更を保存対象にする。
- 空のテキストウィンドウと、閉じることが確定してフェード中のウィンドウはsnapshotから除外する。
- 連続変更は1秒 debounce する。ただし最初の未保存変更から単調時計で最大5秒以内に必ず保存を開始する。
- JSON encode、atomic write、画像 directory scan は utility QoS の専用 serial queue で行い、順序と排他を保証する。
- Quit の `flush()` は pending/retry を cancel し、main thread で snapshot を取得して serial queue 上で同期保存する。
- 非同期保存に失敗した場合、未保存起点を保持し5秒後に再試行する。新しい変更は retry を置き換える。

### 10.2 スキーマと設定の分離

`state.json` の schema version は1。概念形は次の通り。

```json
{
  "version": 1,
  "notes": [
    {
      "id": "UUID",
      "content": { "kind": "text", "text": "..." },
      "frame": { "x": 0, "y": 0, "width": 480, "height": 320 },
      "isPinned": false,
      "fontSizeOffset": 0
    }
  ]
}
```

画像 content は `{ "kind": "image", "image": { "id": "UUID", "fileExtension": "png" } }` とし、原本は `Images/<UUID>.<ext>` に置く。拡張子は小文字ASCII英数字1〜16文字だけを許し、それ以外を `dat` へ正規化して path traversal と任意拡張子を防ぐ。

ノートの並び順は `notes` 配列順。frame、pin、未 clamp の offset をそのまま保存する。
stateはsymbolic linkではないregular file、64 MiB以下、32ノート以下、重複しないnote ID、有限frame、§5.1以内のtextを必須とする。loadとsaveの両方で同じ条件を検証する。

次は `UserDefaults` またはシステム側へ分離し `state.json` に入れない。

- `globalFontSize`
- `localModifier`（旧 `globalModifier` を互換読み込み）
- `lastImageSaveDirectory`
- `newWindowPinMode`（旧 `pinsNewWindowsByDefault` を互換読み込み）
- `hasCompletedOnboarding`
- `suppressPermissionAlert`
- `appLanguage`
- launch-at-login の `SMAppService` 状態

### 10.3 復元

- 起動時に配列順でノートを復元し、保存 frame を §3.6 に従って現在の画面へ収める。
- 復元ではアプリを activate せず、ユーザーの作業中アプリから focus を奪わない。
- テキスト、pin、offset、画像参照、ウィンドウサイズを復元する。
- 画像原本を読み込めないノートは空ウィンドウに化けさせず、表示しない `unrestored` snapshot として保持し、そのセッションの次回保存へそのまま書き戻す。一時的な読込失敗だけで参照と原本を失ってはならない。

### 10.4 破損・未知バージョン・孤児画像

- 読み取り不能な `state.json` は `state.json.corrupt-YYYYMMDD-HHmmss[-N]`、上限・構造違反は`state.json.invalid-YYYYMMDD-HHmmss[-N]`、未知 version は `state.json.version-<version>-YYYYMMDD-HHmmss[-N]` へ rename し、空の表示状態で起動する。state本文は上限+1 byteだけをbounded readし、file sizeの競合で無制限に確保しない。
- quarantine できない場合も crash せず空で起動する。
- state を読めなかったセッションでは画像 prune を禁止し、回収可能性を残す。
- 画像取り込みは原本書込前に共有registryへ登録し、GCの走査・削除とlockで直列化する。main threadでwindowへ取り込んだ後、その時点以降のsnapshotが保存に成功するまで原本を保護する。古いqueued snapshotや保存失敗で解除しない。取り込みをキャンセルした原本は即回収し、初回保存前にclose・置換された原本も次の正常保存で保護を解除する。
- 画像の書き出しは保存先確定時に原本のread handleを確保してからbackgroundへ渡す。close・画像置換・GCでpathが消えても同じ原本を読めるようにし、64 MiB+1のbounded readで増大も検出する。成否を問わずhandleを閉じ、重い読込とencodeはmain threadで行わない。
- 正常保存後、参照集合または取り込み保護集合が前回成功時から変化した場合だけ `Images/` を走査する。
- prune 対象は厳密な `<UUID>.<normalized-ext>` 名を持つ regular file または symbolic link だけ。未参照なら削除する。無関係なファイル、directory、命名不正 entry は触らない。
- directory 列挙または属性取得が失敗した場合は成功扱いにせず、後続保存で再試行できるようにする。

## 11. Input Monitoring と初回起動

### 11.1 権限の用途

Input Monitoring は §2 の listen-only key/mouse event 検出だけに使う。入力監視で受け取ったeventは永続化、ログ出力、network送信しない。ノート本文と画像は§10に従い端末内へ保存するが、network送信しない。許可がなくてもステータスメニューからノートを作成できる。

### 11.2 初回オンボーディング

- `hasCompletedOnboarding == false` のとき、TCC request より先に520×300 ptの non-closable titled windowを中央表示する。
- title は言語非依存の `Ttemp`。
- 冒頭に言語選択を置き、OS preferred language が `ja` prefix なら日本語、それ以外は英語を初期値とする。変更は即時反映する。
- 言語pop-upには表示言語に従う明示的なaccessibility labelを設定する。
- 見出しは `左右 Shift で、どこからでもメモ。 / Press both Shift keys for a note anywhere.`。
- 本文は、ショートカットに macOS Input Monitoring が必要であること、入力監視で得たkey eventを保存・送信しないこと、未許可でもmenu barから使えることだけを簡潔に示す。
- `ログイン時に起動 / Launch at login` は既定ON。
- `続ける / Continue` だけを置き、Returnを割り当てる。
- Continue で初めて login-at-launch の選択、完了 flag、Input Monitoring request を適用する。閉じるだけで完了扱いにしてはならない。

### 11.3 権限状態の追従と導線

- `CGPreflightListenEventAccess()` を正とし、必要なときだけ `CGRequestListenEventAccess()` を呼ぶ。
- 初回未完了中は理由説明より先に request しない。完了済みの未許可起動では request する。
- 未許可中は2秒、許可後は10秒間隔で状態を監視し、timer tolerance は interval の半分とする。
- 許可された瞬間に event tap を開始し、再起動を要求しない。剥奪されたら停止する。
- 未許可時は status symbol、tooltip、accessibility label、右メニューの `入力監視を許可… / Allow Input Monitoring…` で示す。
- 完了済み・未許可の起動では1起動につき1回、`入力監視が必要です / Input Monitoring Required` alertを出し、左右Shiftを使うにはSystem Settingsで許可する旨だけを説明する。`システム設定 / System Settings`、`あとで / Later`、`今後表示しない / Don't show again`を提供する。
- system settings URL は `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`。

## 12. 言語、ビルド、更新、配布

### 12.1 言語

- 対応言語は日本語 `ja` と英語 `en`。
- 未設定時は OS preferred language の先頭が `ja` prefix なら日本語、その他は英語。
- 選択は `appLanguage` へ保存し、通知 `com.am921.ttemp.languageDidChange` で開いている UI を更新する。
- メニュー、設定、onboarding、alert、tooltips、accessibility labels、画像保存の説明は選択言語に従う。固有名、format 名、shortcut 表記はそのままでよい。
- Ttempが所有するUIは上記の選択言語に従う。TCC、Open/Save panel、SparkleなどmacOSまたはframework所有のUIはOS言語に従う。
- About panelは言語非依存の最小構成とし、アプリ内言語とOS言語の混在を見せない。

### 12.2 ビルド構成

- Swift 5、AppKit、macOS deployment target 14.0。
- project generator は XcodeGen、定義は `project.yml`。生成物 `Ttemp.xcodeproj` は source of truth ではない。
- Product name `Ttemp`、Bundle ID `com.am921.ttemp`、marketing version `0.1.0`、build version `1`。development languageは`en`、`CFBundleLocalizations`は`en`と`ja`。
- Swift compiler warningはDebug/Releaseともerrorとして扱う。
- App Sandbox は無効。Hardened Runtime は有効。現行配布は ad-hoc/self signing を前提とする。
- 自己署名にはApple Team IDがないため、本体に限り`com.apple.security.cs.disable-library-validation`を付与する。配布署名では必ず、同梱Sparkleの各architectureのCDHashだけを許すmacOS 14+のlibrary constraintを同時に付ける。OS libraryはOS側で除外される。それ以外の第三者libraryの読込を許してはならない。
- Release は`arm64 x86_64`のUniversal、`ONLY_ACTIVE_ARCH=NO`、`-Osize`、LTO、dead-code stripping、post-processing、reflection metadata `none`。配布ビルドは`generic/platform=macOS`を明示する。
- `LSRequiresNativeExecution=true`で各CPUのnative codeを実行する。Rosetta AOTの変換物は本体のlibrary constraintに一致しないため、Finderから翻訳起動を選べないようにする。CLIによるRosetta強制実行は対応範囲外。Intelの実起動はIntel runnerで検証する。
- AppIcon は asset catalog の10 renditionを全て持ち、16〜1024 pixelの必要 slotを欠かさない。
- menu bar icon は asset ではなく SF Symbols を使う。

### 12.3 Sparkle と network

- 自動更新は Sparkle 2.9.6 のcommit `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`をrevision pinする。
- feed は `https://github.com/RioRio-do/ttemp/releases/latest/download/appcast.xml`。
- EdDSA public key は `XQCyVcCJKpfIsIS9umCNonEODMKebjLmi+3ZhntQkS4=`。秘密鍵を repository、build log、artifact に含めない。
- automatic checks と automatic update を有効にする。
- `SURequireSignedFeed`と`SUVerifyUpdateBeforeExtraction`を有効にし、appcast自体のEdDSA署名とarchive署名を展開前に必須とする。
- updater は単一インスタンス確認後にだけ開始する。manual check 前に app を activate し、dialog が背面に出ないようにする。
- repository link は `https://github.com/RioRio-do/ttemp`。About panel と status menu から開ける。
- 通常のノート機能は network を必要としない。network access は Sparkle update check/download と、ユーザーが明示した GitHub page open に限る。

### 12.4 Release

- `scripts/build-release.sh` はtracked fileがcleanなcommitからだけ実行し、署名済みRelease app、初回インストール用`Ttemp.dmg`、Sparkle更新用`Ttemp.zip`、各EdDSA signature、署名済み`appcast.xml`、`SHA256SUMS`を再現可能な手順で生成する。
- `scripts/sign-app.sh`はSparkleのInstaller、Autoupdate、Updater、Downloader、framework、本体を内側から順に同じ証明書とHardened Runtimeで署名する。Downloaderのvendor entitlementsを維持し、helperへ本体のlibrary-validation例外を付けない。`--deep`は検証専用とし署名には使わない。
- DMGは660×400 pointのFinder icon viewとし、背景の文字は`Ttemp`だけ、中央に右向き矢印を置く。左に`Ttemp.app`、右に`/Applications`を指す`Applications` symlinkを置き、言語依存の注釈は表示しない。
- DMG生成時は一時HFS+ imageのFinder設定を保存してからUDZOへ圧縮する。checksum、`Ttemp.app`、Applications symlink、背景、`.DS_Store`、内部appのcode signatureと実起動を公開前に検証し、作業中に作られる`.fseventsd`やSpotlight管理情報を配布物へ含めない。
- ZIPはSparkle enclosure専用とし、appcastはDMGではなく`Ttemp.zip`を参照する。ZIP展開後のappも実起動検証する。`scripts/verify-update.swift`はappの`SUPublicEDKey`でZIPとappcastのEdDSA署名を独立検証し、署名必須設定、version/build、archive length、canonical download URLも照合する。
- GitHub Releaseには`Ttemp.dmg`、`Ttemp.zip`、`appcast.xml`、`SHA256SUMS`を添付し、READMEではDMGを通常ユーザー向けのダウンロードとして案内する。checksumは破損・取り違え検出用で、publisherの独立認証とは表現しない。
- 初回artifactは自己署名・未公証であることをREADMEへ明示し、canonical GitHub Release以外からの取得を案内しない。初回起動をGatekeeperに止められた場合はApple公式手順へのリンクと、System Settings → Privacy & Security → `このまま開く / Open Anyway`を案内し、quarantine属性をcommandで削除させない。破損・malware警告の無視を案内しない。Developer ID署名とApple公証へ移行するまで、macOSが初回配布元をpublisherまで検証できないリスクを残存事項として扱う。
- 公開READMEは日本語の`README.md`と英語の`README.en.md`を分け、同じ行へ日英を重ねない。
- Release buildは、symlink解決・path標準化後のbundle URLが`/Applications`の真の子でなければruntimeを初期化しない。alertはtitleを`Ttemp を Applications へ / Move Ttemp to Applications`、本文を移動後に再度開く旨の1文、buttonを`Finder で表示 / Show in Finder`と`終了 / Quit`だけにする。要求時は現在のappをFinderで表示して終了する。Debug buildは開発場所から実行できるようこの制約を適用しない。
- `scripts/setup-release-keys.sh` と `docs/SIGNING.md` を signing/setup の運用手順とする。
- 既存 PKCS#12 は certificate/private key を保持したまま macOS 15 の Security.framework と互換なコンテナへ再梱包し、certificate SHA-256 fingerprint の一致を置換条件とする。
- CI の signing certificate は repository secrets から Release job 専用の使い捨て user keychain へ取り込み、user/System trust store は変更しない。PKCS#12 の復号、certificate CN と fingerprint の一致を確認し、fingerprint を Xcode の signing identity として明示する。秘密鍵ACLは当該job内の全processに限って開き、keychainと復号済みファイルは成功・失敗を問わずcleanupする。
- CIはXcodeGen 2.46.0の公式release assetをSHA-256 `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`で検証して使う。workflow既定権限は`contents: read`、checkoutはcredentialを永続化せず、Release jobだけ`contents: write`を持つ。
- Release作成前に既存tagがbuilt `GITHUB_SHA`と異なれば失敗し、`gh release create --target "$GITHUB_SHA"`でartifactとsource commitを固定する。
- Release の明示的な抑止は、main へ push された最後の commit の件名が `[skip release]` で始まる場合に限る。
- GitHub Actions は main 更新を起点に build/test/release を行う場合でも、秘密鍵を repository へ書き出さず、公開 asset の signature を検証可能に保つ。

## 13. テストと継続的検証

### 13.1 自動テスト

unit test は App host を起動せず、次の純粋ロジックと永続化境界を直接検証する。

- Shift chord の成立、無効化、reset。
- window placement と復元 clamp。
- plain text sanitize と pasteboard priority/mode transition。
- global/offset font model、shortcut、modifier migration。
- image point sizing、format list、actual ImageIO conversion。
- image store の原本保持、形式判定、regular-file/byte/frame/pixel上限、display image。
- state round-trip、debounce/max-delay、monotonic clock、retry、byte/note/text/ID上限、quarantine、extension normalization/path traversal 防止、managed-file 限定 prune、非同期画像取り込みと保存・削除の競合。
- 日本語/英語選択と pin-mode migration。
- Applications配下判定のdirect/nested path、DMG path、類似prefix、境界値。

### 13.2 CI の最低ゲート

CI は少なくとも次を行う。

1. 固定versionとSHA-256を検証したXcodeGenでprojectを生成し、Sparkleの固定revisionを解決する。
2. code signing を無効化した Debug app build を明示的に成功させる。
3. `TtempTests` を実行して全 test を成功させる。
4. PRでも使い捨て自己署名証明書でUniversal Releaseを生成し、`scripts/test-release.sh`で実起動、ZIP往復、第三者library拒否、制約を外した負例、署名検証器の負例とローカルSparkle更新を検証する。本番秘密鍵は使わない。
5. 1〜4はmacOS 15 arm64 / Intel、macOS 26 arm64で行い、全成功を固定名`ビルドとテスト`で集約する。branch protectionのrequired context名を変更しない。
6. Release workflowでは本番identityで再ビルドし、DMG/ZIP/appcastの存在・構造・署名情報と最終artifactの実起動を検証する。

### 13.3 配布版の隔離診断

- 本体の`--self-test`は一意な一時state directory、専用UserDefaults suite、専用copy/paste用pasteboardを使う。既存メモ、一般クリップボード、ログイン項目を変更せず、TCC要求・event tap・ネットワーク更新を開始しない。
- 明示的な診断モードに限りApplications制約と単一インスタンス制約を外し、通常のcontrollerでstatus item、日英メニュー、テキスト入力・paste・undo/redo・上限、文字サイズ・pin、画像import、状態保存復元、close時copy、最後のwindow後の常駐を検証する。成功markerと終了codeを両方要求し、外部watchdogを45秒にする。
- `--probe-library PATH`は`--self-test`専用。実在する署名済み第三者dylibがOSのlibrary constraintで拒否されることを確認する。
- `--isolated`は同じ隔離データで手動UI確認用の空メモを開く。通常のmain menuと言語変更経路を使い、login設定は専用defaults内だけで模擬する。正常終了時に診断データを破棄する。
- `scripts/test-update.sh`は同じ固定revisionのSparkle CLIをbuildし、一意なbundle IDのappコピーと使い捨てEdDSA鍵、127.0.0.1だけのfeedで署名不正の拒否・helperによる更新・更新後の実起動を確認する。実アプリと公開feedは変更しない。

### 13.4 手動確認

OS/TCC/AppKit UI 依存で unit test 化しにくい項目は release 前に実機確認する。

- 初回 onboarding → TCC、拒否、後日許可、即時 tap 開始、剥奪。
- 左右 Shift の物理キー、JIS/US配列、Caps Lock、mouse混在。
- 複数 display/Spaces、focus handoff、pin、空 windowの自動消滅。
- text/image paste、Finder file URL、drag/drop、animated image、巨大画像。
- light/dark、日本語/英語、VoiceOver label、Retina menu thumbnail/AppIcon。
- login item の enable、requires approval、disable。
- Sparkle manual/automatic update と署名不一致の拒否。

## 14. 定数、非目標、監査規則

### 14.1 主要定数

| 項目 | 値 |
| --- | --- |
| 新規ノート | 480×320 pt |
| 最小コンテンツ | 200×150 pt |
| 画像表示上限 | visible frame の60% |
| 新規配置 bias / cascade | 8%上 / 24 pt右下 |
| fade / shake | 0.12秒 / 0.24秒、最大8 pt |
| global font | 既定14、9〜48 pt、step 1 |
| scroll threshold | coarse 3、precise 24 |
| 表示画像 downsample | 最大辺4096 pixel超 |
| 本文 / ノート数 | 262,144 UTF-16 code unit / 32枚 |
| 画像取込 | encoded 64 MiB、100 frame、累積64,000,000 pixel |
| state読込 | 64 MiB |
| JPEG/HEIC quality | 0.9 |
| menu title / thumbnail | 30文字 / 48×16 pt |
| state save | debounce 1秒、最大遅延5秒、retry 5秒 |
| permission poll | 未許可2秒、許可後10秒、設定画面2秒 |
| Settings / Onboarding / About | 460×300 / 520×300 / 300×210 pt |

### 14.2 非目標

- rich text、複数画像、画像とテキストの混在編集。
- cloud sync、account、analytics、telemetry、入力内容のnetwork送信。
- iOS/iPadOS/Windows/Linux/Mac App Store対応。
- global shortcut のカスタマイズ。
- sandbox 化、document-based app、通常のDock app化。
- 画像編集、crop、quality slider、gallery管理。

### 14.3 変更時の監査

挙動を変更するcommitは、同じ変更内で本書、関連test、source commentを同期する。完了前に少なくとも次を確認する。

1. XcodeGen生成、Debug build、unit tests、Release build、static analyze が成功する。
2. `git diff --check`、plist、shell script、asset catalog、workflow構文に破損がない。
3. state と image の失敗時に既存データを不可逆に消さない。
4. 重いdisk/image処理がmain threadへ戻っていない。
5. permission、clipboard、single-instance、focus、login item の境界動作を再確認する。
6. 本書と `README.md`、`docs/SIGNING.md`、`project.yml`、実装の定数・文言に矛盾がない。
