import AppKit
import CoreGraphics

/// 入力監視（Input Monitoring）権限の状態監視（SPEC §11.3）。
///
/// 定期的にチェックし、承認された瞬間に通知する。アプリの再起動を不要にするため。
final class PermissionMonitor {
    /// 権限状態が変化したときに呼ばれる（初回は必ず呼ばれる）
    var onAuthorizationChanged: ((Bool) -> Void)?

    private var timer: Timer?
    private var lastValue: Bool?

    static var isAuthorized: Bool { CGPreflightListenEventAccess() }

    func start(requestIfNeeded: Bool) {
        let granted = Self.isAuthorized
        if !granted, requestIfNeeded {
            requestAccess()
        }
        // 初回は必ず変化として通知され、タイマーもここで張られる
        emit(granted)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// TCC のダイアログを出す。ユーザーが許可するまで戻り値は false のまま。
    func requestAccess() {
        guard !Self.isAuthorized else { return }
        CGRequestListenEventAccess()
    }

    /// システム設定の「プライバシーとセキュリティ → 入力監視」を開く（SPEC §11.3）。
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    private func emit(_ value: Bool) {
        guard value != lastValue else { return }
        lastValue = value
        onAuthorizationChanged?(value)
        scheduleTimer()
    }

    /// 未許可の間は「承認された瞬間」を素早く拾うため 2 秒間隔。
    /// 許可後は剥奪（稀）の監視だけなので 10 秒に落とす。
    /// tolerance を与えて OS に他のウェイクアップとまとめさせる（常駐アプリの省電力）。
    private func scheduleTimer() {
        timer?.invalidate()
        let interval: TimeInterval = lastValue == true ? 10.0 : 2.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.emit(Self.isAuthorized)
        }
        timer.tolerance = interval / 2
        // 既定モードだけだとメニュー展開中やライブリサイズ中は権限監視が止まる
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
