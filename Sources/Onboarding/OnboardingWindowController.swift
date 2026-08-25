import AppKit

/// 初回起動時の説明画面（SPEC §11.3）。
///
/// なぜ入力監視が必要かを説明し、システム設定への導線と
/// 「ログイン時に起動」（デフォルト ON）を同じ画面に置く。
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private var window: NSWindow?
    private var launchAtLoginCheckbox: NSButton?
    private var onFinish: (() -> Void)?

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        super.init()
    }

    func show(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Ttemp へようこそ"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let heading = NSTextField(labelWithString: "左右の Shift を同時に押すと、どこからでもメモが開きます。")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: """
        この操作を検知するために、Ttemp は macOS の「入力監視」の許可を必要とします。\
        Ttemp はキーの押下を読み取るだけで、内容の記録や送信は一切行いません。

        許可しない場合でも、メニューバーのアイコンから「新規ウィンドウ」で使えます。\
        許可はあとから与えても、再起動なしでそのまま有効になります。
        """)
        body.font = .systemFont(ofSize: 13)
        body.preferredMaxLayoutWidth = 460

        // SPEC §11.3: 同じ画面に「ログイン時に起動」（デフォルト ON）を置く
        let checkbox = NSButton(checkboxWithTitle: "ログイン時に Ttemp を起動する", target: nil, action: nil)
        checkbox.state = .on
        launchAtLoginCheckbox = checkbox

        let openButton = NSButton(title: "システム設定を開く", target: self, action: #selector(openSettings))
        let startButton = NSButton(title: "はじめる", target: self, action: #selector(finish))
        startButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [openButton, startButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [heading, body, checkbox, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

        let contentView = NSView()
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
        window.contentView = contentView
        return window
    }

    @objc private func openSettings() {
        PermissionMonitor.openSystemSettings()
    }

    @objc private func finish() {
        // チェックが入っていれば（デフォルト ON）ログイン項目を登録する
        preferences.launchAtLogin = launchAtLoginCheckbox?.state == .on
        preferences.hasCompletedOnboarding = true
        window?.close()
        onFinish?()
    }

    func windowWillClose(_ notification: Notification) {
        // 閉じるボタンで閉じた場合も「表示済み」にする（毎回出続けるのを避ける）
        preferences.hasCompletedOnboarding = true
    }
}
