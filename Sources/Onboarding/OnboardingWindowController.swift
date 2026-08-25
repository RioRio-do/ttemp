import AppKit

/// 初回起動時の説明画面（SPEC §11.3）。
///
/// なぜ入力監視が必要かを説明し、システム設定への導線と
/// 「ログイン時に起動」（デフォルト ON）を同じ画面に置く。
/// 冒頭に表示言語の選択を置く（初期値は OS の言語。選ぶと画面ごと切り替わる）。
final class OnboardingWindowController: NSObject {
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
                              // 初回説明を閉じるボタンだけで完了扱いにすると、既定 ON の
                              // ログイン項目も権限要求も適用されない。明示的な「続ける」で完了する。
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        applyContent(to: window)
        return window
    }

    /// 文言を含むビュー階層を組む。言語切替時はここを呼び直して丸ごと差し替える
    private func applyContent(to window: NSWindow) {
        window.title = "Ttemp"

        // 表示言語（初期値は OS の言語）
        let popUp = NSPopUpButton()
        popUp.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        popUp.selectItem(at: AppLanguage.allCases.firstIndex(of: L10n.current) ?? 0)
        popUp.target = self
        popUp.action = #selector(languageChanged)
        popUp.setAccessibilityLabel(L10n.pick("言語", "Language"))
        languagePopUp = popUp
        let languageRow = NSStackView(views: [NSTextField(labelWithString: L10n.pick("言語", "Language")),
                                              popUp])
        languageRow.orientation = .horizontal
        languageRow.spacing = 8

        let heading = NSTextField(labelWithString: L10n.pick(
            "左右 Shift で、どこからでもメモ。",
            "Press both Shift keys for a note anywhere."))
        heading.font = .systemFont(ofSize: 15, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: L10n.pick("""
        このショートカットには macOS の「入力監視」が必要です。\
        入力監視で得たキーイベントは保存・送信しません。

        許可しなくても、メニューバーから使えます。
        """, """
        This shortcut needs macOS Input Monitoring. \
        Key events received through it are never stored or sent.

        You can still use Ttemp from the menu bar without it.
        """))
        body.font = .systemFont(ofSize: 13)
        body.preferredMaxLayoutWidth = 460

        // SPEC §11.3: 同じ画面に「ログイン時に起動」（デフォルト ON）を置く
        let checkbox = NSButton(checkboxWithTitle: L10n.pick("ログイン時に起動",
                                                             "Launch at login"),
                                target: self,
                                action: #selector(launchAtLoginToggled))
        checkbox.state = launchAtLoginChecked ? .on : .off
        launchAtLoginCheckbox = checkbox

        let startButton = NSButton(title: L10n.pick("続ける", "Continue"),
                                   target: self, action: #selector(finish))
        startButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [languageRow, heading, body, checkbox, startButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

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

    @objc private func finish() {
        // チェックが入っていれば（デフォルト ON）ログイン項目を登録する
        preferences.launchAtLogin = launchAtLoginChecked
        preferences.hasCompletedOnboarding = true
        window?.close()
        onFinish?()
    }
}
