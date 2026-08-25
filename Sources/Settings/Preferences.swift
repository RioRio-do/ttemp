import Foundation
import ServiceManagement

/// アプリ設定（SPEC §10.2: state.json とは分離して `UserDefaults` に持つ）。
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let globalFontSize = "globalFontSize"
        static let localModifier = "localModifier"
        /// 旧: グローバル操作の修飾キー。⌘=グローバル固定へ仕様変更した際に
        /// ローカル側の設定として引き継ぐ（値は control / option で共通）
        static let legacyGlobalModifier = "globalModifier"
        static let lastImageSaveDirectory = "lastImageSaveDirectory"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let suppressPermissionAlert = "suppressPermissionAlert"
        static let newWindowPinMode = "newWindowPinMode"
        /// 旧: Bool の「新規ウィンドウを最前面に固定する」。3択へ移行する際の読み替え用
        static let legacyPinsNewWindowsByDefault = "pinsNewWindowsByDefault"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// SPEC §7.1: グローバル文字サイズ。範囲外の値は保持せずクランプする。
    var globalFontSize: CGFloat {
        get {
            guard defaults.object(forKey: Key.globalFontSize) != nil else {
                return FontSizeModel.defaultGlobalSize
            }
            return FontSizeModel.clampGlobal(CGFloat(defaults.double(forKey: Key.globalFontSize)))
        }
        set { defaults.set(Double(FontSizeModel.clampGlobal(newValue)), forKey: Key.globalFontSize) }
    }

    /// SPEC §7.3: ローカル文字サイズ操作の修飾キー（グローバルは ⌘ 固定）。
    var localModifier: LocalModifier {
        get {
            if let raw = defaults.string(forKey: Key.localModifier),
               let value = LocalModifier(rawValue: raw) {
                return value
            }
            // 旧「グローバル操作の修飾キー」設定からの引き継ぎ
            if let raw = defaults.string(forKey: Key.legacyGlobalModifier),
               let value = LocalModifier(rawValue: raw) {
                return value
            }
            return .control
        }
        set { defaults.set(newValue.rawValue, forKey: Key.localModifier) }
    }

    /// SPEC §8.2: 画像の前回保存先ディレクトリ。
    var lastImageSaveDirectory: URL? {
        get {
            guard let path = defaults.string(forKey: Key.lastImageSaveDirectory) else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set { defaults.set(newValue?.path, forKey: Key.lastImageSaveDirectory) }
    }

    /// SPEC §9: 新規ウィンドウの最前面固定の既定（3択）。
    var newWindowPinMode: NewWindowPinMode {
        get {
            if let raw = defaults.string(forKey: Key.newWindowPinMode),
               let value = NewWindowPinMode(rawValue: raw) {
                return value
            }
            // 旧 Bool 設定からの移行（true だった場合は「固定する（空でも残す）」相当）
            if defaults.object(forKey: Key.legacyPinsNewWindowsByDefault) != nil {
                return defaults.bool(forKey: Key.legacyPinsNewWindowsByDefault) ? .pinnedKeepEmpty : .unpinned
            }
            // SPEC §9: 既定は「固定する（空になったら消す）」
            return .pinnedDismissEmpty
        }
        set { defaults.set(newValue.rawValue, forKey: Key.newWindowPinMode) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    /// SPEC §11.3: 起動時の「入力監視が未許可」アラートを今後表示しない
    var suppressPermissionAlert: Bool {
        get { defaults.bool(forKey: Key.suppressPermissionAlert) }
        set { defaults.set(newValue, forKey: Key.suppressPermissionAlert) }
    }

    // MARK: - ログイン時に起動（SPEC §1 / §9）

    /// `SMAppService` の状態はシステム側が持つため `UserDefaults` には持たない。
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            let service = SMAppService.mainApp
            do {
                if newValue {
                    switch service.status {
                    case .enabled:
                        break
                    case .requiresApproval:
                        // 登録済みだがユーザーが無効化している。再 register は
                        // already-registered になるため、承認できるシステム画面を開く。
                        SMAppService.openSystemSettingsLoginItems()
                    case .notRegistered, .notFound:
                        try service.register()
                    @unknown default:
                        try service.register()
                    }
                } else {
                    // requiresApproval も「登録済み」。ここで解除しないと、UI 上は OFF でも
                    // システムには保留中のログイン項目が残り続ける。
                    switch service.status {
                    case .enabled, .requiresApproval:
                        try service.unregister()
                    case .notRegistered, .notFound:
                        break
                    @unknown default:
                        try service.unregister()
                    }
                }
            } catch {
                NSLog("[Ttemp] ログイン項目の更新に失敗した: \(error.localizedDescription)")
            }
        }
    }
}
