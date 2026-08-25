import AppKit

/// ペースト／ドロップ内容の受け口。モード遷移の判定は `NoteWindowController` が担う。
protocol NotePasteHandling: AnyObject {
    /// - Returns: 内容を受け付けたか（false ならビュー側は既定の動作を行わない）
    func handlePasteboard(_ pasteboard: NSPasteboard, isDrop: Bool) -> Bool
}

/// ノートのテキスト入力ビュー（SPEC §5）。
final class NoteTextView: NSTextView {
    /// Escape でウィンドウを閉じる要求（SPEC §3.5）
    var onEscape: (() -> Void)?
    /// ペースト／ドロップの受け口
    weak var pasteHandler: NotePasteHandling?
    /// SPEC §7.2: ⌘/⌃ + スクロールによる文字サイズ変更。消費したら true を返す
    var scrollHandler: ((NSEvent) -> Bool)?
    /// SPEC §8.1: 右クリックメニュー（標準のサブメニューは出さない）
    var contextMenuProvider: (() -> NSMenu?)?

    // MARK: - セットアップ

    /// SPEC §5.2: macOS の自動処理をすべて OFF にする。
    func applyPlainTextConfiguration(fontSize: CGFloat) {
        // macOS 13+ の NSTextView は TextKit 2 が既定だが、長文のライブリサイズ中に
        // 折り返しや表示位置が跳ねて不安定になる。layoutManager に触れて TextKit 1
        // （互換モード）に固定する。プレーンテキストのみなので機能面の不足はない。
        _ = layoutManager

        isRichText = false
        importsGraphics = false
        allowsImageEditing = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        // SPEC §5.2: 切らないと入力した URL に自動でリンク属性が付く
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        // 自動大文字化に対応する専用プロパティは存在しないため、
        // テキストチェック自体を全種類無効化して合わせて潰す（SPEC §5.2）。
        enabledTextCheckingTypes = 0

        // SPEC §5.1: 検索・置換は NSTextView 標準の find bar を使う
        usesFindBar = true
        isIncrementalSearchingEnabled = true

        // SPEC §5.1: Tab はタブ文字を挿入する（フォーカス移動先が他にない）
        isFieldEditor = false

        allowsUndo = true
        isEditable = true
        isSelectable = true
        // 背景は自分で塗る。透明にすると、この階層で不透明なのはウィンドウの
        // フレームビュー（＝contentView より後ろ）だけになり、消したグリフの矩形や
        // スクロールで露出した領域を塗り潰す主体がビュー階層内に一人もいなくなる。
        // 結果として文字の消し残り・スクロール時の尾引きが出る。
        // ウィンドウの背景色と同じ色なので見た目は変わらず、合成が減るぶん速い。
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textColor = .textColor
        insertionPointColor = .textColor
        font = Self.font(ofSize: fontSize)
        // SPEC §3.5: 内側余白 12pt
        textContainerInset = NSSize(width: 12, height: 12)
        textContainer?.lineFragmentPadding = 0
    }

    static func font(ofSize size: CGFloat) -> NSFont {
        // SPEC §5.1: システムフォント（SF Pro / ヒラギノ）
        NSFont.systemFont(ofSize: size)
    }

    /// SPEC §7: 実効文字サイズを適用する。既存テキストにも即座に反映する。
    func applyFontSize(_ size: CGFloat) {
        let newFont = Self.font(ofSize: size)
        guard font != newFont else { return }
        font = newFont
        typingAttributes[.font] = newFont
        if let textStorage {
            textStorage.addAttribute(.font,
                                     value: newFont,
                                     range: NSRange(location: 0, length: textStorage.length))
        }
    }

    // MARK: - キー操作

    override func insertTab(_ sender: Any?) {
        // SPEC §5.1: Tab はフォーカス移動ではなくタブ文字の挿入
        insertText("\t", replacementRange: selectedRange())
    }

    override func cancelOperation(_ sender: Any?) {
        // SPEC §3.5: IME の未確定文字がある間は IME に委ねる
        if hasMarkedText() {
            super.cancelOperation(sender)
            return
        }
        // SPEC §3.5: find bar 表示中は find bar を閉じるだけ。もう一度押すと閉じる
        if let scrollView = enclosingScrollView, scrollView.isFindBarVisible {
            scrollView.isFindBarVisible = false
            window?.makeFirstResponder(self)
            return
        }
        onEscape?()
    }

    /// scrollWheel を override すると AppKit は responsive scrolling を無効化し、
    /// 通常のスクロールが引っかかる感触になる。修飾キーなしのイベントは必ず super に
    /// 渡すので、互換を明示してネイティブなスクロールに戻す。
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if scrollHandler?(event) == true { return }
        super.scrollWheel(with: event)
    }

    // MARK: - ペースト

    override func paste(_ sender: Any?) {
        // SPEC §5.4 / §6.1: 判定とモード遷移は NoteWindowController に委ねる
        _ = pasteHandler?.handlePasteboard(.general, isDrop: false)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    // MARK: - ドラッグ&ドロップ（SPEC §6.3）

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        pasteHandler == nil ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        pasteHandler == nil ? super.draggingUpdated(sender) : .copy
    }

    /// `NSTextView` の既定実装は自分が扱える型でなければ false を返し、その場合
    /// `performDragOperation` は呼ばれない。受け入れ判定は `PasteboardReader` に
    /// 一本化しているので、ここは常に通して handler に渡す。
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        pasteHandler == nil ? super.prepareForDragOperation(sender) : true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pasteHandler else { return super.performDragOperation(sender) }
        return pasteHandler.handlePasteboard(sender.draggingPasteboard, isDrop: true)
    }

    func insertSanitized(_ raw: String) {
        // IME の未確定文字が残ったまま textStorage を直接書き換えると、marked range と
        // 実際の文字列が食い違って以降の入力が壊れる。先に確定させてから差し込む。
        if hasMarkedText() {
            unmarkText()
        }
        let sanitized = PlainTextSanitizer.sanitize(raw)
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: sanitized) else { return }
        let insertedLength = (sanitized as NSString).length
        if let textStorage {
            textStorage.replaceCharacters(in: range, with: sanitized)
            // `replaceCharacters(in:with:)` は直前の文字の属性を引き継ぐだけなので、
            // 差し込んだ範囲を全ウィンドウ共通のフォント／色に揃える。
            // 本文の残りは既に揃っているため、毎回そこまで塗り直して
            // 全文レイアウトをやり直す必要はない。
            textStorage.setAttributes(typingAttributes,
                                      range: NSRange(location: range.location, length: insertedLength))
        }
        didChangeText()
        setSelectedRange(NSRange(location: range.location + insertedLength, length: 0))
        // 長文を貼ると挿入末尾（＝キャレット）が可視範囲の外に出たままになるので追従させる
        scrollRangeToVisible(selectedRange())
    }

    // MARK: - 右クリックメニュー

    override func menu(for event: NSEvent) -> NSMenu? {
        // SPEC §8.1: NSTextView がデフォルトで付ける「スペルと文法」「変換」「音声」
        // 「サービス」等のサブメニューは出さない。必要な項目だけを自前で組む。
        guard let contextMenuProvider else { return super.menu(for: event) }
        selectWordIfClickedOutsideSelection(for: event)
        return contextMenuProvider()
    }

    /// 標準の `NSTextView` は右クリック時にカーソル下の単語を選択してからメニューを出す。
    /// `menu(for:)` を丸ごと差し替えるとこの副作用が失われ、「カット」「コピー」が
    /// 見当違いの選択範囲に効いてしまうため、選択だけ再現する。
    private func selectWordIfClickedOutsideSelection(for event: NSEvent) {
        let text = string as NSString
        guard text.length > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let index = min(characterIndexForInsertion(at: point), text.length - 1)
        // 既存の選択範囲の中を右クリックした場合はその選択を保つ（標準どおり）
        guard !NSLocationInRange(index, selectedRange()) else { return }
        // 単語の境界はテキストビュー自身の判定に任せる（日本語の分かち書きも含む）
        setSelectedRange(selectionRange(forProposedRange: NSRange(location: index, length: 0),
                                        granularity: .selectByWord))
    }
}
