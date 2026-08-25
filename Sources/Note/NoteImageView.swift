import AppKit

/// 画像モードの表示ビュー（SPEC §6.2 / §6.3）。
final class NoteImageView: NSImageView {
    /// ペースト／ドロップの受け口（モード遷移の判定は `NoteWindowController` が行う）
    weak var pasteHandler: NotePasteHandling?
    /// 右クリックメニューの供給元
    var menuProvider: (() -> NSMenu?)?
    /// ⌘C（SPEC §14 の未決事項に対する決定: 「画像をコピー」と同じ動作にする）
    var onCopy: (() -> Void)?
    /// SPEC §7.2: ⌘/⌃ + スクロール。消費したら true を返す
    var scrollHandler: ((NSEvent) -> Bool)?
    /// SPEC §3.5: Escape でウィンドウを閉じる（画像モードにもテキストと同じ導線が要る）
    var onEscape: (() -> Void)?

    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        // SPEC §6.2: アスペクト比を保ってフィットし、レターボックスで表示、切り抜きはしない。
        // 拡大はしない（下限サイズでは「中央に等倍表示」する必要があるため）。
        imageScaling = .scaleProportionallyDown
        imageAlignment = .alignCenter
        isEditable = false
        // SPEC §6.3: GIF は通常は1枚目を静止表示
        animates = false
        registerForDraggedTypes(PasteboardReader.acceptedDragTypes)
    }

    // MARK: - GIF のホバー再生（SPEC §6.3 / PLAN §3.8）

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        animates = true
    }

    override func mouseExited(with event: NSEvent) {
        animates = false
    }

    // MARK: - キー操作・メニュー

    override var acceptsFirstResponder: Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    /// SPEC §14 の未決事項に対する決定: 画像モードの ⌘C は「画像をコピー」と同じ動作にする。
    /// `NSImageView` は `copy(_:)` を持たないので、レスポンダチェーン用に自前で生やす。
    @objc func copy(_ sender: Any?) {
        onCopy?()
    }

    @objc func paste(_ sender: Any?) {
        // SPEC §6.1: 画像モード中の画像は置き換え、テキストは拒否。判定は handler 側。
        _ = pasteHandler?.handlePasteboard(.general, isDrop: false)
    }

    /// SPEC §14 の未決事項に対する決定: 画像モードの ⌘A は何もしない（選択の概念がない）。
    override func selectAll(_ sender: Any?) {}

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func scrollWheel(with event: NSEvent) {
        if scrollHandler?(event) == true { return }
        super.scrollWheel(with: event)
    }

    // MARK: - ドラッグ&ドロップ（SPEC §6.3）

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        pasteHandler == nil ? [] : .copy
    }

    /// ドロップの可否を最終的に決めるのは `draggingEntered` ではなく `draggingUpdated` の
    /// 戻り値。`NSImageView` は自前の実装を持っていて `isEditable == false` では
    /// `NSDragOperationNone` を返すため、これを上書きしないと画像モードのウィンドウへ
    /// 画像をドロップして差し替える操作が黙って失敗する。
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        pasteHandler == nil ? [] : .copy
    }

    /// 同じ理由で `prepareForDragOperation` も上書きする（false だと
    /// `performDragOperation` が呼ばれない）。
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        pasteHandler != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        pasteHandler?.handlePasteboard(sender.draggingPasteboard, isDrop: true) ?? false
    }
}
