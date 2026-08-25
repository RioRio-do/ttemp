import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SPEC §1: 2つ目のインスタンスは既存インスタンスに「全ウィンドウを前面に」を依頼して終了する
    static let bringAllToFrontNotification = Notification.Name("com.am921.ttemp.bringAllToFront")

    private let preferences = Preferences.shared
    private let stateStore = StateStore()
    private lazy var windowManager = WindowManager(preferences: preferences, stateStore: stateStore)
    private let eventTap = EventTapController()
    private let permissionMonitor = PermissionMonitor()
    private var statusItemController: StatusItemController?
    private lazy var settingsController = SettingsWindowController(
        preferences: preferences,
        globalFontSize: (get: { [weak self] in self?.windowManager.globalFontSize ?? FontSizeModel.defaultGlobalSize },
                         set: { [weak self] size in self?.windowManager.globalFontSize = size })
    )
    private lazy var onboardingController = OnboardingWindowController(preferences: preferences)

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !terminateIfAlreadyRunning() else { return }

        // SPEC §1: Dock アイコンなし
        NSApp.setActivationPolicy(.accessory)
        MainMenuBuilder.install()

        let statusItem = StatusItemController(windowManager: windowManager)
        statusItem.onOpenSettings = { [weak self] in self?.settingsController.show() }
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

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleBringAllToFront),
            name: Self.bringAllToFrontNotification,
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
        } else {
            permissionMonitor.start(requestIfNeeded: false)
            onboardingController.show { [weak self] in
                self?.permissionMonitor.requestAccess()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionMonitor.stop()
        eventTap.stop()
        // SPEC §10.1: Quit 時にも保存する。ウィンドウを閉じる前に行う（閉じてからでは
        // スナップショットが空になる）。
        stateStore.flush()
        // SPEC §4: Quit は「閉じる」ではないのでクリップボードにコピーしない
        windowManager.closeAllWithoutCopying()
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
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != .current }
        guard !others.isEmpty else { return false }

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
}
