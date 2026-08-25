import AppKit

/// 設定画面（SPEC §9）。言語を含む6項目だけに絞る。
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    /// グローバル文字サイズの読み書き（WindowManager 経由で全ウィンドウに反映させる）
    private let globalFontSizeBinding: (get: () -> CGFloat, set: (CGFloat) -> Void)

    private var window: NSWindow?
    private var languagePopUp: NSPopUpButton?
    private var modifierPopUp: NSPopUpButton?
    private var launchAtLoginCheckbox: NSButton?
    private var defaultPinPopUp: NSPopUpButton?
    private var fontSizeField: NSTextField?
    private var fontSizeStepper: NSStepper?
    private var permissionLabel: NSTextField?
    private var permissionButton: NSButton?
    private var permissionTimer: Timer?
    private var languageObserver: NSObjectProtocol?

    init(preferences: Preferences = .shared,
         globalFontSize: (get: () -> CGFloat, set: (CGFloat) -> Void)) {
        self.preferences = preferences
        self.globalFontSizeBinding = globalFontSize
        super.init()

        // 言語が切り替わったら（この画面の言語ポップアップ経由を含む）表示を作り直す。
        // ポップアップのアクション中に contentView を差し替えないよう1サイクル遅らせる。
        languageObserver = NotificationCenter.default.addObserver(forName: L10n.didChangeNotification,
                                                                  object: nil,
                                                                  queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildForLanguageChange() }
        }
    }

    deinit {
        permissionTimer?.invalidate()
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }

    private func rebuildForLanguageChange() {
        guard let window else { return }
        window.title = L10n.pick("設定", "Settings")
        window.contentView = makeContentView()
        refresh()
    }

    func show() {
        let isFirstShow = window == nil
        if window == nil {
            window = makeWindow()
        }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        // 初回だけ中央に置く。毎回呼ぶと、ユーザーが動かした位置が開くたびに戻る
        if isFirstShow {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        startPermissionPolling()
    }

    /// グローバル文字サイズが他所（⌃; など）で変わったときに表示を追従させる
    func updateFontSizeDisplay(_ size: CGFloat) {
        fontSizeField?.stringValue = String(Int(size.rounded()))
        fontSizeStepper?.doubleValue = Double(size)
    }

    // MARK: - 組み立て

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = L10n.pick("設定", "Settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = makeContentView()
        return window
    }

    /// 設定項目のビュー階層。言語切替時に丸ごと作り直せるよう window とは分けておく
    private func makeContentView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        // 0. 表示言語（メニュー・設定・アラートに即時反映される）
        let langPopUp = NSPopUpButton()
        langPopUp.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        langPopUp.target = self
        langPopUp.action = #selector(languageChanged)
        langPopUp.setAccessibilityLabel(L10n.pick("言語", "Language"))
        languagePopUp = langPopUp
        stack.addArrangedSubview(row(label: L10n.pick("言語", "Language"), control: langPopUp))

        // 1. ローカル文字サイズ操作の修飾キー（SPEC §7.3。グローバルは ⌘ 固定）
        let popUp = NSPopUpButton()
        popUp.addItems(withTitles: LocalModifier.allCases.map(\.displayName))
        popUp.target = self
        popUp.action = #selector(modifierChanged)
        popUp.setAccessibilityLabel(L10n.pick("個別操作キー", "Per-window key"))
        modifierPopUp = popUp
        stack.addArrangedSubview(row(label: L10n.pick("個別操作キー", "Per-window key"),
                                     control: popUp))

        // 2. デフォルト文字サイズ（SPEC §9: 9〜48pt）
        let field = NSTextField(string: "")
        field.alignment = .right
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: Double(FontSizeModel.minSize))
        formatter.maximum = NSNumber(value: Double(FontSizeModel.maxSize))
        field.formatter = formatter
        field.target = self
        field.action = #selector(fontSizeFieldChanged)
        field.setAccessibilityLabel(L10n.pick("文字サイズ", "Font size"))
        field.widthAnchor.constraint(equalToConstant: 56).isActive = true
        fontSizeField = field

        let stepper = NSStepper()
        stepper.minValue = Double(FontSizeModel.minSize)
        stepper.maxValue = Double(FontSizeModel.maxSize)
        stepper.increment = Double(FontSizeModel.step)
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(fontSizeStepperChanged)
        stepper.setAccessibilityLabel(L10n.pick("文字サイズ", "Font size"))
        fontSizeStepper = stepper

        let sizeStack = NSStackView(views: [field, stepper, NSTextField(labelWithString: "pt")])
        sizeStack.orientation = .horizontal
        sizeStack.spacing = 6
        stack.addArrangedSubview(row(label: L10n.pick("文字サイズ", "Font size"),
                                     control: sizeStack))

        // 3. 新規ウィンドウの最前面固定の既定（SPEC §9）
        let pinPopUp = NSPopUpButton()
        pinPopUp.addItems(withTitles: NewWindowPinMode.allCases.map(\.displayName))
        pinPopUp.target = self
        pinPopUp.action = #selector(defaultPinModeChanged)
        pinPopUp.setAccessibilityLabel(L10n.pick("新規ウィンドウを固定", "Pin new windows"))
        defaultPinPopUp = pinPopUp
        stack.addArrangedSubview(row(label: L10n.pick("新規ウィンドウを固定", "Pin new windows"),
                                     control: pinPopUp))

        // 4. ログイン時に起動（SPEC §1）
        let checkbox = NSButton(checkboxWithTitle: L10n.pick("ログイン時に起動", "Launch at login"),
                                target: self,
                                action: #selector(launchAtLoginChanged))
        launchAtLoginCheckbox = checkbox
        stack.addArrangedSubview(checkbox)

        // 5. 入力監視権限の状態（SPEC §11.3）
        let statusLabel = NSTextField(labelWithString: "")
        permissionLabel = statusLabel
        let openButton = NSButton(title: L10n.pick("システム設定", "System Settings"),
                                  target: self,
                                  action: #selector(openPermissionSettings))
        permissionButton = openButton
        let permissionStack = NSStackView(views: [statusLabel, openButton])
        permissionStack.orientation = .horizontal
        permissionStack.spacing = 12
        stack.addArrangedSubview(row(label: L10n.pick("入力監視", "Input Monitoring"),
                                     control: permissionStack))

        let contentView = NSView()
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
        ])
        return contentView
    }

    private func row(label: String, control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let stack = NSStackView(views: [title, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }

    // MARK: - 表示の更新

    private func refresh() {
        languagePopUp?.selectItem(at: AppLanguage.allCases.firstIndex(of: L10n.current) ?? 0)
        modifierPopUp?.selectItem(at: LocalModifier.allCases.firstIndex(of: preferences.localModifier) ?? 0)
        launchAtLoginCheckbox?.state = preferences.launchAtLogin ? .on : .off
        defaultPinPopUp?.selectItem(at: NewWindowPinMode.allCases.firstIndex(of: preferences.newWindowPinMode) ?? 0)
        updateFontSizeDisplay(globalFontSizeBinding.get())
        updatePermissionStatus()
    }

    private func updatePermissionStatus() {
        let authorized = PermissionMonitor.isAuthorized
        let status = authorized
            ? L10n.pick("許可済み", "Allowed")
            : L10n.pick("未許可", "Not allowed")
        permissionLabel?.stringValue = status
        permissionLabel?.setAccessibilityLabel(
            L10n.pick("入力監視：\(status)", "Input Monitoring: \(status)")
        )
        permissionButton?.isHidden = authorized
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updatePermissionStatus()
        }
        timer.tolerance = 1.0
        // 既定モードだけだとポップアップ展開中やライブリサイズ中に止まる
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    func windowWillClose(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: - 操作

    @objc private func languageChanged() {
        guard let index = languagePopUp?.indexOfSelectedItem,
              AppLanguage.allCases.indices.contains(index) else { return }
        L10n.current = AppLanguage.allCases[index]
    }

    @objc private func modifierChanged() {
        guard let index = modifierPopUp?.indexOfSelectedItem,
              LocalModifier.allCases.indices.contains(index) else { return }
        preferences.localModifier = LocalModifier.allCases[index]
    }

    @objc private func defaultPinModeChanged() {
        guard let index = defaultPinPopUp?.indexOfSelectedItem,
              NewWindowPinMode.allCases.indices.contains(index) else { return }
        preferences.newWindowPinMode = NewWindowPinMode.allCases[index]
    }

    @objc private func launchAtLoginChanged() {
        preferences.launchAtLogin = launchAtLoginCheckbox?.state == .on
        // 登録に失敗した場合は実際の状態に戻す
        launchAtLoginCheckbox?.state = preferences.launchAtLogin ? .on : .off
    }

    @objc private func fontSizeFieldChanged() {
        guard let value = fontSizeField?.doubleValue else { return }
        apply(fontSize: CGFloat(value))
    }

    @objc private func fontSizeStepperChanged() {
        guard let value = fontSizeStepper?.doubleValue else { return }
        apply(fontSize: CGFloat(value))
    }

    private func apply(fontSize: CGFloat) {
        let clamped = FontSizeModel.clampGlobal(fontSize)
        globalFontSizeBinding.set(clamped)
        updateFontSizeDisplay(clamped)
    }

    @objc private func openPermissionSettings() {
        PermissionMonitor.openSystemSettings()
    }
}
