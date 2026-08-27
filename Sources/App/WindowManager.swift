import AppKit

/// 全ノートウィンドウの生成・破棄・一覧・前面化（SPEC §3）と、
/// 永続化される状態のスナップショット（SPEC §10）。
final class WindowManager {
    private(set) var controllers: [NoteWindowController] = []

    private let preferences: Preferences
    private let stateStore: StateStore
    private let imageStore: ImageStore
    private let clipboard: NSPasteboard

    /// 起動時に復元できなかったノート（画像を読めなかったもの）。
    /// ウィンドウは出さないが、次の保存でそのまま書き戻すために保持する。
    /// 落とすと state.json から消え、`StateStore` の孤児掃除で画像の原本まで削除される。
    private var unrestoredNotes: [NoteSnapshot] = []

    /// SPEC §7.1: グローバル文字サイズ。変更すると全ウィンドウが相対関係を保って追従する。
    var globalFontSize: CGFloat {
        get { preferences.globalFontSize }
        set {
            let clamped = FontSizeModel.clampGlobal(newValue)
            guard clamped != preferences.globalFontSize else { return }
            preferences.globalFontSize = clamped
            for controller in controllers {
                controller.applyGlobalFontSize(clamped)
            }
            onGlobalFontSizeChanged?(clamped)
        }
    }

    /// 設定画面の表示を追従させるための通知
    var onGlobalFontSizeChanged: ((CGFloat) -> Void)?

    init(preferences: Preferences = .shared, stateStore: StateStore, clipboard: NSPasteboard = .general) {
        self.preferences = preferences
        self.stateStore = stateStore
        self.imageStore = ImageStore(directory: stateStore.imagesDirectoryURL,
                                     pendingImports: stateStore.pendingImageImports)
        self.clipboard = clipboard
    }

    // MARK: - 生成

    /// 左右 Shift／メニューバーからの新規ウィンドウ（SPEC §3.1）。
    func createNoteActivating() {
        guard controllers.count + unrestoredNotes.count < StateStore.maximumNoteCount else {
            NSSound.beep()
            return
        }
        // SPEC §3.1: 協調的アクティベーション（`NSApp.activate()`）では
        // 他アプリからの譲渡がなく無視され、ウィンドウが前面のアプリの背後に出てしまう。
        // 非推奨だが従来挙動の ignoringOtherApps を使う。
        NSApp.activate(ignoringOtherApps: true)

        let controller = makeController(frame: nextFrame())
        // SPEC §9: 新規ウィンドウの最前面固定の既定値（復元時は保存された値を使うのでここでは効かない）
        controller.isPinned = preferences.newWindowPinMode.pinsNewWindows
        controller.present(activating: true)
    }

    private func makeController(id: UUID = UUID(), frame: NSRect) -> NoteWindowController {
        let controller = NoteWindowController(id: id,
                                              frame: frame,
                                              globalFontSize: globalFontSize,
                                              imageStore: imageStore,
                                              preferences: preferences,
                                              clipboard: clipboard)
        controller.onClosed = { [weak self] controller in
            self?.handleClosed(controller)
        }
        controller.onRestoreFocus = { Self.yieldFocusToNextFrontmostApp() }
        controller.onStateChanged = { [weak self] in
            self?.stateStore.scheduleSave()
        }
        // SPEC §7.1: グローバル値を変更すると全ウィンドウが相対関係を保って追従する
        controller.onGlobalFontSizeChange = { [weak self] direction in
            guard let self else { return }
            if let direction {
                globalFontSize = FontSizeModel.bumpGlobal(globalFontSize, direction: direction)
            } else {
                globalFontSize = FontSizeModel.defaultGlobalSize
            }
        }
        controllers.append(controller)
        return controller
    }

    /// SPEC §3.6: マウスカーソルがあるディスプレイの中央やや上。既存と重なればカスケード。
    private func nextFrame() -> NSRect {
        let visibleFrame = Self.screenUnderCursor()?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let occupied = controllers.map { $0.window.frame.origin }
        return WindowPlacement.frame(in: visibleFrame, occupiedOrigins: occupied)
    }

    private static func screenUnderCursor() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    // MARK: - 永続化（SPEC §10）

    func snapshot() -> AppState {
        // 復元できなかったノートも必ず書き戻す（一時的な読み込み失敗を不可逆にしない）
        AppState(notes: unrestoredNotes + controllers.compactMap { $0.snapshot })
    }

    /// SPEC §10.3: アプリは非アクティブのままウィンドウだけ表示する。
    func restore(_ state: AppState) {
        let visibleFrames = NSScreen.screens.map { $0.visibleFrame }
        let fallback = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        for note in state.notes {
            let frame = WindowPlacement.restoredFrame(saved: note.frame.rect,
                                                      visibleFrames: visibleFrames,
                                                      fallback: fallback)
            let controller = makeController(id: note.id, frame: frame)
            guard controller.restore(from: note) else {
                // ウィンドウは出さずに畳み、スナップショットだけ次回に持ち越す
                controller.closeWithoutCopying()
                controllers.removeAll { $0 === controller }
                unrestoredNotes.append(note)
                continue
            }
            controller.present(activating: false)
        }
    }

    // MARK: - 前面化

    /// SPEC §3.4: メニューバー左クリック時。全ウィンドウを前面に持ってくる。
    func bringAllToFront() {
        // ウィンドウがない左クリックで、意味なく作業中アプリからフォーカスを奪わない。
        guard !controllers.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        for controller in controllers {
            controller.orderFront()
        }
        controllers.last?.window.makeKeyAndOrderFront(nil)
    }

    /// SPEC §8.3: メニューバー右クリックのウィンドウ一覧から個別に前面化する。
    func focus(_ controller: NoteWindowController) {
        guard controllers.contains(where: { $0 === controller }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.window.makeKeyAndOrderFront(nil)
    }

    // MARK: - 終了

    /// SPEC §4: Quit ではコピーしない。
    func closeAllWithoutCopying() {
        for controller in controllers {
            controller.closeWithoutCopying()
        }
        controllers.removeAll()
    }

    // MARK: - フォーカス管理

    private func handleClosed(_ controller: NoteWindowController) {
        controllers.removeAll { $0 === controller }
        // 閉じたウィンドウを state から落とすため保存し直す
        stateStore.scheduleSave()
    }

    /// SPEC §4: 閉じる操作の開始時、自アプリの次に前面へウィンドウを出しているアプリへ
    /// フォーカスを譲る。close() 後の OS 任せのハンドオフだと、直下とは限らない任意の
    /// アプリへ一瞬フォーカスが渡り、無関係なウィンドウがちらつく。
    /// `NSApp.hide(nil)` は採らない（ピン留め等で残したウィンドウまで隠れるため）。
    private static func yieldFocusToNextFrontmostApp() {
        guard NSApp.isActive, let target = FocusRestoreTarget.nextFrontmostApp() else { return }
        target.activate()
    }
}
