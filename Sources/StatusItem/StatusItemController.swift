import AppKit

/// メニューバーアイコン（SPEC §3.4 / §8.3）。
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let windowManager: WindowManager
    private var showsPermissionWarning = false

    /// SPEC §8.3: 「設定…」
    var onOpenSettings: (() -> Void)?
    /// 「最新版を確認…」。Sparkle の updater（AppDelegate 持ち）に委ねる
    var onCheckForUpdates: (() -> Void)?

    /// SPEC §8.3 の未決事項に対する決定: 一覧のサムネイルは高さ16ptに揃える
    private static let thumbnailHeight: CGFloat = 16

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        // PLAN §3.6: statusItem.menu を設定すると左クリックでもメニューが開いてしまう
        if let button = statusItem.button {
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
            button.action = #selector(handleClick)
        }
        updateImage()

        // 言語切替でツールチップを追従させる（メニューは表示のたびに組み直すので不要）
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(languageDidChange),
                                               name: L10n.didChangeNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func languageDidChange() {
        updateImage()
    }

    /// SPEC §11.3: 権限が未付与／剥奪されたらアイコンに警告を出す。
    func setPermissionWarning(_ warning: Bool) {
        showsPermissionWarning = warning
        updateImage()
    }

    private func updateImage() {
        guard let button = statusItem.button else { return }
        // SPEC §12: メニューバーアイコンは SF Symbol の t.square（テンプレート画像）
        let symbol = showsPermissionWarning ? "exclamationmark.triangle" : "t.square"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Ttemp")
        image?.isTemplate = true
        button.image = image
        button.toolTip = showsPermissionWarning
            ? L10n.pick("Ttemp — 入力監視が未許可のため左右 Shift が反応しません",
                        "Ttemp — Left+Right Shift is disabled: Input Monitoring not allowed")
            : "Ttemp"
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            // SPEC §3.4: 左クリックで全ウィンドウを前面に
            windowManager.bringAllToFront()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        // SPEC §8.3: 入力監視が未付与でもアプリを使えるようにするため必ず置く
        menu.addItem(withTitle: L10n.pick("新規ウィンドウ", "New Window"),
                     action: #selector(newWindow), keyEquivalent: "")
            .target = self

        if showsPermissionWarning {
            menu.addItem(.separator())
            let item = menu.addItem(withTitle: L10n.pick("入力監視を許可…", "Allow Input Monitoring…"),
                                    action: #selector(openPermissionSettings),
                                    keyEquivalent: "")
            item.target = self
        }

        // SPEC §8.3: 開いているウィンドウ一覧。クリックでそのウィンドウにフォーカス
        if !windowManager.controllers.isEmpty {
            menu.addItem(.separator())
            for controller in windowManager.controllers {
                let item = menu.addItem(withTitle: controller.menuTitle,
                                        action: #selector(focusWindow(_:)),
                                        keyEquivalent: "")
                item.target = self
                item.representedObject = controller
                if let thumbnail = controller.menuThumbnail {
                    item.image = Self.scaledThumbnail(thumbnail)
                }
            }
            menu.addItem(.separator())
            let allItem = menu.addItem(withTitle: L10n.pick("すべてのウィンドウを前面に", "Bring All Windows to Front"),
                                       action: #selector(bringAllToFront),
                                       keyEquivalent: "")
            allItem.target = self
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.pick("Ttemp について", "About Ttemp"),
                     action: #selector(showAbout), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: L10n.pick("最新版を確認…", "Check for Updates…"),
                     action: #selector(checkForUpdates), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: L10n.pick("GitHub ページを開く", "Open GitHub Page"),
                     action: #selector(openGitHub), keyEquivalent: "")
            .target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.pick("設定…", "Settings…"),
                     action: #selector(openSettings), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: L10n.pick("Ttemp を終了", "Quit Ttemp"),
                     action: #selector(quit), keyEquivalent: "")
            .target = self

        // PLAN §3.6: 表示直後に menu を外して左クリック分岐を保つ
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func newWindow() {
        windowManager.createNoteActivating()
    }

    @objc private func focusWindow(_ sender: NSMenuItem) {
        guard let controller = sender.representedObject as? NoteWindowController else { return }
        windowManager.focus(controller)
    }

    @objc private func bringAllToFront() {
        windowManager.bringAllToFront()
    }

    @objc private func openPermissionSettings() {
        PermissionMonitor.openSystemSettings()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    // MARK: - About / 更新確認

    @objc private func showAbout() {
        AboutPanel.show()
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(AppInfo.repositoryURL)
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    private static func scaledThumbnail(_ image: NSImage) -> NSImage {
        let ratio = image.size.height > 0 ? image.size.width / image.size.height : 1
        let size = NSSize(width: max(1, thumbnailHeight * ratio), height: thumbnailHeight)
        // lockFocus はビットマップを1つの解像度で焼き込むため Retina で潰れる。
        // drawingHandler なら描画先のスケールで都度描かれる。
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
