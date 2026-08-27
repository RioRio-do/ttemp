import Foundation

/// 表示言語。
enum AppLanguage: String, CaseIterable {
    case japanese = "ja"
    case english = "en"

    /// OS の優先言語から導く既定値（未選択時と、初回起動の言語選択の初期値）
    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ja") == true ? .japanese : .english
    }

    /// 言語選択 UI の表示名。どの言語で表示中でも自分自身の言語で出す
    var displayName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }
}

/// 実行時切替できる最小の i18n 機構。
///
/// `.strings` ではなくコード内に日英を並べて持つ:
/// - 文字列は数十個で、キーのタイプミスをコンパイラが防げる
/// - `AppleLanguages` の差し替えと違い、再起動なしで切り替わる
///   （メニュー類は表示のたびに組み立て直しているのでそのまま追従する）
///
/// `Preferences` ではなく `UserDefaults` を直接読むのは、テストターゲットにも
/// 含まれる displayName 系（ImageExportFormat など）から参照されるため。
enum L10n {
    /// Diagnostics and tests use an isolated preferences domain.
    static var defaults: UserDefaults = .standard
    static let defaultsKey = "appLanguage"
    /// 言語が切り替わったとき。開きっぱなしのウィンドウ（設定画面など）が拾って作り直す
    static let didChangeNotification = Notification.Name("com.am921.ttemp.languageDidChange")

    static var current: AppLanguage {
        get {
            if let raw = defaults.string(forKey: defaultsKey),
               let language = AppLanguage(rawValue: raw) {
                return language
            }
            return .systemDefault
        }
        set {
            guard newValue != current else { return }
            defaults.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static func pick(_ ja: String, _ en: String) -> String {
        current == .japanese ? ja : en
    }
}
