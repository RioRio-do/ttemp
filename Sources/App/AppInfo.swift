import Foundation

/// アプリ自身のメタ情報と配布元リポジトリへのリンク。
enum AppInfo {
    /// 配布元の GitHub リポジトリ。「GitHub を開く」「最新版を確認…」が参照する。
    static let repositoryOwner = "RioRio-do"
    static let repositoryName = "Ttemp"

    static var repositoryURL: URL {
        URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)")!
    }

    static var releasesURL: URL {
        repositoryURL.appendingPathComponent("releases")
    }

    /// GitHub Releases の最新リリース取得 API
    static var latestReleaseAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases/latest")!
    }

    /// Info.plist の CFBundleShortVersionString（project.yml の MARKETING_VERSION 由来）。
    /// テストバンドルなど取得できない文脈では "0" を返す。
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
