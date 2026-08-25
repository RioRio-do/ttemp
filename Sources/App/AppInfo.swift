import Foundation

/// アプリ自身のメタ情報と配布元リポジトリへのリンク。
/// 更新の確認・配布は Sparkle（Info.plist の SUFeedURL）が担う。
enum AppInfo {
    /// 配布元の GitHub リポジトリ。「GitHub を開く」と About パネルが参照する。
    static let repositoryOwner = "RioRio-do"
    static let repositoryName = "ttemp"

    static var repositoryURL: URL {
        URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)")!
    }

    /// About panel は言語依存の接頭辞を置かず、version/build の値だけを表示する。
    static var displayVersion: String {
        let dictionary = Bundle.main.infoDictionary
        let version = dictionary?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = dictionary?["CFBundleVersion"] as? String,
              !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}
