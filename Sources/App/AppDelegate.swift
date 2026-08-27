import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SPEC §1: 2つ目のインスタンスは既存インスタンスに「全ウィンドウを前面に」を依頼して終了する
    static let bringAllToFrontNotification = Notification.Name("com.am921.ttemp.bringAllToFront")

    private let preferences: Preferences
    private let stateStore: StateStore
    private let diagnostics: RuntimeDiagnostics?
    private lazy var windowManager = WindowManager(preferences: preferences, stateStore: stateStore,
                                                   clipboard: diagnostics?.clipboard ?? .general)
    private let eventTap = EventTapController()
    private let permissionMonitor = PermissionMonitor()
    private var hasStartedRuntime = false
    private var statusItemController: StatusItemController?
    private lazy var settingsController = SettingsWindowController(
        preferences: preferences,
        globalFontSize: (get: { [weak self] in self?.windowManager.globalFontSize ?? FontSizeModel.defaultGlobalSize },
                         set: { [weak self] size in self?.windowManager.globalFontSize = size })
    )
    private lazy var onboardingController = OnboardingWindowController(preferences: preferences)
    /// 自動更新（docs/SIGNING.md）。生成した時点で定期チェックが動き出す
    private lazy var updaterController = SPUStandardUpdaterController(startingUpdater: diagnostics == nil,
                                                                      updaterDelegate: nil,
                                                                      userDriverDelegate: nil)

    init(diagnostics: RuntimeDiagnostics? = nil) {
        self.diagnostics = diagnostics
        preferences = diagnostics?.preferences ?? .shared
        stateStore = diagnostics?.stateStore ?? StateStore()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard diagnostics != nil || !terminateIfAlreadyRunning() else { return }
#if !DEBUG
        guard diagnostics != nil || continueOnlyIfInstalledInApplications() else { return }
#endif
        hasStartedRuntime = true

        // SPEC §1: Dock アイコンなし
        NSApp.setActivationPolicy(.accessory)
        MainMenuBuilder.install()
        // 多重起動側では updater を開始しない。単一インスタンス確認後にだけ初期化する。
        _ = updaterController

        let statusItem = StatusItemController(windowManager: windowManager)
        statusItem.onOpenSettings = { [weak self] in self?.settingsController.show() }
        statusItem.onCheckForUpdates = { [weak self] in
            guard self?.diagnostics == nil else { return }
            // LSUIElement のアプリは非アクティブのままだと Sparkle のダイアログが背面に出る
            NSApp.activate(ignoringOtherApps: true)
            self?.updaterController.checkForUpdates(nil)
        }
        statusItemController = statusItem

        // ⌃; などでグローバル値が変わったら設定画面の表示も追従させる
        windowManager.onGlobalFontSizeChanged = { [weak self] size in
            self?.settingsController.updateFontSizeDisplay(size)
        }

        // SPEC §10: 状態の復元と逐次保存
        stateStore.snapshotProvider = { [weak self] in
            self?.windowManager.snapshot() ?? AppState()
        }
        restoreState()

        // Exercise the signed production startup and controllers without touching
        // real notes, preferences, login items, clipboard, TCC, or update servers.
        if let diagnostics {
            diagnostics.start(windowManager: windowManager, statusItem: statusItem,
                              updater: updaterController.updater)
            return
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleBringAllToFront),
            name: Self.bringAllToFrontNotification,
            object: nil
        )

        // 言語切替でメインメニュー（⌘V などのキー割り当ての親）を組み立て直す
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: L10n.didChangeNotification,
            object: nil
        )

        eventTap.onChordFired = { [weak self] in
            self?.windowManager.createNoteActivating()
        }

        // SPEC §11.3: 承認された瞬間に自動でタップを開始する（再起動不要）
        permissionMonitor.onAuthorizationChanged = { [weak self] granted in
            guard let self else { return }
            self.statusItemController?.setPermissionWarning(!granted)
            if granted {
                self.eventTap.start()
            } else {
                self.eventTap.stop()
            }
        }
        // SPEC §11.3: 初回起動時は、TCC のダイアログを出す前に理由を説明する
        if preferences.hasCompletedOnboarding {
            permissionMonitor.start(requestIfNeeded: true)
            // メニューバーの「!」アイコンだけでは気づきにくいので、明示的に知らせる。
            // TCC のダイアログは一度拒否すると二度と出ないため、その後の起動では
            // このアラートが唯一の導線になる。
            showPermissionAlertIfNeeded()
        } else {
            permissionMonitor.start(requestIfNeeded: false)
            onboardingController.show { [weak self] in
                self?.permissionMonitor.requestAccess()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 多重起動側やApplications外の起動では、runtimeを一度も初期化していない。
        guard hasStartedRuntime else { return }
        permissionMonitor.stop()
        eventTap.stop()
        // SPEC §10.1: Quit 時にも保存する。ウィンドウを閉じる前に行う（閉じてからでは
        // スナップショットが空になる）。
        stateStore.flush()
        // SPEC §4: Quit は「閉じる」ではないのでクリップボードにコピーしない
        windowManager.closeAllWithoutCopying()
        diagnostics?.cleanup()
    }

    /// メインメニュー（MainMenuBuilder）の「Ttemp について」から呼ばれる
    @objc func showAboutPanel(_ sender: Any?) {
        AboutPanel.show()
    }

    // MARK: - インストール場所（SPEC §12.4）

    /// Release版をDMGやDownloadsから直接常用させず、/Applicationsへの配置を案内する。
    private func continueOnlyIfInstalledInApplications() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        guard !ApplicationLocation.isInstalled(bundleURL: bundleURL) else { return true }

        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.pick("Ttemp を Applications へ",
                                      "Move Ttemp to Applications")
        alert.informativeText = L10n.pick(
            "Ttemp を Applications に移して、もう一度開いてください。",
            "Move Ttemp to Applications, then open it again."
        )
        alert.addButton(withTitle: L10n.pick("Finder で表示", "Show in Finder"))
        alert.addButton(withTitle: L10n.pick("終了", "Quit"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
        }
        NSApp.terminate(nil)
        return false
    }

    // MARK: - 入力監視の未許可アラート（SPEC §11.3）

    /// 未許可のまま起動したら、1起動につき1回だけアラートで知らせる。
    /// 「今後表示しない」でオプトアウトできる（メニューバーの警告アイコンは残る）。
    private func showPermissionAlertIfNeeded() {
        guard !PermissionMonitor.isAuthorized, !preferences.suppressPermissionAlert else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !PermissionMonitor.isAuthorized else { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L10n.pick("入力監視が必要です",
                                          "Input Monitoring Required")
            alert.informativeText = L10n.pick(
                "左右 Shift を使うには、システム設定で Ttemp を許可してください。",
                "Allow Ttemp in System Settings to use both Shift keys.")
            alert.addButton(withTitle: L10n.pick("システム設定", "System Settings"))
            alert.addButton(withTitle: L10n.pick("あとで", "Later"))
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = L10n.pick("今後表示しない", "Don't show again")
            let response = alert.runModal()
            if alert.suppressionButton?.state == .on {
                self.preferences.suppressPermissionAlert = true
            }
            if response == .alertFirstButtonReturn {
                PermissionMonitor.openSystemSettings()
            }
        }
    }

    // MARK: - 復元

    private func restoreState() {
        switch stateStore.load() {
        case .loaded(let state):
            windowManager.restore(state)
        case .empty:
            break
        case .recovered(let backupURL):
            // SPEC §10.4: 復元を諦めて空の状態で起動し、壊れたファイルは残す
            NSLog("[Ttemp] 状態ファイルを読めなかったため空で起動した。退避先: \(backupURL.path)")
        }
    }

    /// SPEC §1: ウィンドウが0枚でもプロセスは生存する
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - 多重起動

    private func terminateIfAlreadyRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = NSRunningApplication.current
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != current }
        guard !others.isEmpty else { return false }

        // ほぼ同時に2プロセスが起動すると、単に「他がいる」で判定した場合は双方が
        // 相手を見つけて終了し得る。起動日時（同値／取得不能なら PID）で全プロセスが
        // 同じ勝者を選び、勝者だけが起動を続ける。
        let winner = ([current] + others).min { lhs, rhs in
            if let lhsDate = lhs.launchDate, let rhsDate = rhs.launchDate,
               lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.processIdentifier < rhs.processIdentifier
        }
        guard winner?.processIdentifier != current.processIdentifier else { return false }

        DistributedNotificationCenter.default().postNotificationName(
            Self.bringAllToFrontNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        NSApp.terminate(nil)
        return true
    }

    @objc private func handleBringAllToFront() {
        windowManager.bringAllToFront()
    }

    @objc private func handleLanguageChange() {
        MainMenuBuilder.install()
    }
}
