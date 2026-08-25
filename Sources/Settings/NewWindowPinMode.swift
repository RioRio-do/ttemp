import Foundation

/// SPEC §9: 新規ウィンドウの最前面固定の既定。
///
/// SPEC §3.2 の「ピン留め中は空でも自動消滅しない」を、ユーザーが選べるようにしたもの。
enum NewWindowPinMode: String, CaseIterable {
    /// 固定しない（SPEC §3.3 の基本挙動）
    case unpinned
    /// 固定するが、空になったウィンドウはフォーカスを外すと自動消滅する
    case pinnedDismissEmpty
    /// 固定し、空でも自動消滅しない（SPEC §3.2 のピン留めの原則どおり）
    case pinnedKeepEmpty

    var displayName: String {
        switch self {
        case .unpinned: return L10n.pick("固定しない", "Don't pin")
        case .pinnedDismissEmpty: return L10n.pick("固定する（空になったら消す）",
                                                   "Pin (dismiss when empty)")
        case .pinnedKeepEmpty: return L10n.pick("固定する（空でも残す）",
                                                "Pin (keep even when empty)")
        }
    }

    /// 新規ウィンドウを最前面固定で作るか
    var pinsNewWindows: Bool {
        self != .unpinned
    }

    /// ピン留め中でも、空ならフォーカスアウトで自動消滅させるか
    var dismissesEmptyWhilePinned: Bool {
        self == .pinnedDismissEmpty
    }
}
