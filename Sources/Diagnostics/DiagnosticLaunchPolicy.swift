import Foundation

/// An accidental-launch guard, not a security boundary: callers control their environment.
/// Data isolation alone does not isolate macOS's bundle-ID-based menu-bar records.
enum DiagnosticLaunchPolicy {
    static let productionIdentifier = "com.am921.ttemp"
    static let developmentIdentifier = "com.am921.ttemp.development"

    static func isTestIdentifier(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        if identifier == developmentIdentifier { return true }
        return ["com.am921.ttemp.runtime-test.", "com.am921.ttemp.update-test."].contains { prefix in
            guard identifier.hasPrefix(prefix) else { return false }
            let suffix = String(identifier.dropFirst(prefix.count))
            guard let uuid = UUID(uuidString: suffix) else { return false }
            return uuid.uuidString.caseInsensitiveCompare(suffix) == .orderedSame
        }
    }

    static func allows(identifier: String?, interactive: Bool, disposableCI: Bool,
                       environment: [String: String]) -> Bool {
        if isTestIdentifier(identifier) { return !disposableCI }
        return identifier == productionIdentifier && !interactive && disposableCI
            && environment["TTEMP_DISPOSABLE_CI"] == "1"
            && environment["GITHUB_ACTIONS"] == "true"
            && environment["RUNNER_ENVIRONMENT"] == "github-hosted"
            && environment["RUNNER_OS"] == "macOS"
    }
}
