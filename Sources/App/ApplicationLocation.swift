import Foundation

/// Release版を、ログイン項目や自動更新が安定する /Applications 配下に限定するための判定。
enum ApplicationLocation {
    static let systemApplicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

    static func isInstalled(
        bundleURL: URL,
        applicationsURL: URL = systemApplicationsURL
    ) -> Bool {
        let bundleComponents = canonicalComponents(of: bundleURL)
        let applicationsComponents = canonicalComponents(of: applicationsURL)

        guard bundleComponents.count > applicationsComponents.count else { return false }
        return bundleComponents.prefix(applicationsComponents.count)
            .elementsEqual(applicationsComponents)
    }

    private static func canonicalComponents(of url: URL) -> [String] {
        url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    }
}
