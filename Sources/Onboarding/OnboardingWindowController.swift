import AppKit

/// 初回起動時の説明画面（SPEC §11.3）。
///
/// なぜ入力監視が必要かを説明し、システム設定への導線と
/// 「ログイン時に起動」（デフォルト ON）を同じ画面に置く。
/// 冒頭に表示言語の選択を置く（初期値は OS の言語。選ぶと画面ごと切り替わる）。
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private var window: NSWindow?
    private var languagePopUp: NSPopUpButton?
    private var launchAtLoginCheckbox: NSButton?
    /// 言語切替で画面を作り直してもチェック状態を保つ（既定 ON）
    private var launchAtLoginChecked = true
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self
        applyContent(to: window)
        return window
    }

    /// 文言を含むビュー階層を組む。言語切替時はここを呼び直して丸ごと差し替える
    private func applyContent(to window: NSWindow) {
        window.title = L10n.pick("Ttemp へようこそ", "Welcome to Ttemp")

        // 表示言語（初期値は OS の言語）
        let popUp = NSPopUpButton()
        popUp.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        popUp.selectItem(at: AppLanguage.allCases.firstIndex(of: L10n.current) ?? 0)
        popUp.target = self
        popUp.action = #selector(languageChanged)
        languagePopUp = popUp
        let languageRow = NSStackView(views: [NSTextField(labelWithString: L10n.pick("言語:", "Language:")),
                                              popUp])
        languageRow.orientation = .horizontal
        languageRow.spacing = 8

        let heading = NSTextField(labelWithString: L10n.pick(
            "左右の Shift を同時に押すと、どこからでもメモが開きます。",
            "Press both Shift keys to open a note from anywhere."))
        heading.font = .systemFont(ofSize: 15, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: L10n.pick("""
        この操作を検知するために、Ttemp は macOS の「入力監視」の許可を必要とします。\
        Ttemp はキーの押下を読み取るだけで、内容の記録や送信は一切行いません。

        許可しない場合でも、メニューバーのアイコンから「新規ウィンドウ」で使えます。\
        許可はあとから与えても、再起動なしでそのまま有効になります。
        """, """
        To detect this gesture, Ttemp needs macOS Input Monitoring permission. \
        Ttemp only observes key presses; it never records or transmits what you type.

        Without the permission you can still use "New Window" from the menu bar icon. \
        Granting it later takes effect immediately, no restart needed.
        """))
        body.font = .systemFont(ofSize: 13)
        body.preferredMaxLayoutWidth = 460

        // SPEC §11.3: 同じ画面に「ログイン時に起動」（デフォルト ON）を置く
        let checkbox = NSButton(checkboxWithTitle: L10n.pick("ログイン時に Ttemp を起動する",
                                                             "Launch Ttemp at login"),
                                target: self,
                                action: #selector(launchAtLoginToggled))
        checkbox.state = launchAtLoginChecked ? .on : .off
        launchAtLoginCheckbox = checkbox

        let openButton = NSButton(title: L10n.pick("システム設定を開く", "Open System Settings"),
                                  target: self, action: #selector(openSettings))
        let startButton = NSButton(title: L10n.pick("はじめる", "Get Started"),
                                   target: self, action: #selector(finish))
        startButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [openButton, startButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [languageRow, heading, body, checkbox, buttons])
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
    }

    @objc private func languageChanged() {
        guard let index = languagePopUp?.indexOfSelectedItem,
              AppLanguage.allCases.indices.contains(index) else { return }
        L10n.current = AppLanguage.allCases[index]
        // ポップアップのアクション中にビュー階層を壊さないよう1サイクル遅らせて作り直す
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.applyContent(to: window)
        }
    }

    @objc private func launchAtLoginToggled() {
        launchAtLoginChecked = launchAtLoginCheckbox?.state == .on
    }

    @objc private func openSettings() {
        PermissionMonitor.openSystemSettings()
    }

    @objc private func finish() {
        // チェックが入っていれば（デフォルト ON）ログイン項目を登録する
        preferences.launchAtLogin = launchAtLoginChecked
        preferences.hasCompletedOnboarding = true
        window?.close()
        onFinish?()
    }

    func windowWillClose(_ notification: Notification) {
        // 閉じるボタンで閉じた場合も「表示済み」にする（毎回出続けるのを避ける）
        preferences.hasCompletedOnboarding = true
    }
}
