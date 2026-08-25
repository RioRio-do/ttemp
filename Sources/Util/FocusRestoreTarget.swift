import AppKit

/// SPEC §4: ウィンドウを閉じたあとのフォーカス復帰先。
/// 「記憶しておいた直前のアプリ」ではなく、閉じる時点で自アプリの次に前面へ
/// ウィンドウを出しているアプリを、画面のZ順（CGWindowList）から求める。
enum FocusRestoreTarget {
    /// 自アプリ以外で最前面に通常ウィンドウを表示しているアプリを返す。
    static func nextFrontmostApp() -> NSRunningApplication? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // 一覧は前面→背面の順。レイヤー0（通常ウィンドウ）に絞ることで、
        // メニューバー・Dock・ステータスアイテム等のシステム面を除外する。
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular, !app.isTerminated else { continue }
            return app
        }
        return nil
    }
}
