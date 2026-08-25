import XCTest

final class ApplicationLocationTests: XCTestCase {
    private let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

    func testDirectApplicationIsInstalled() {
        let app = URL(fileURLWithPath: "/Applications/Ttemp.app", isDirectory: true)
        XCTAssertTrue(ApplicationLocation.isInstalled(bundleURL: app,
                                                      applicationsURL: applicationsURL))
    }

    func testNestedApplicationIsInstalled() {
        let app = URL(fileURLWithPath: "/Applications/Utilities/Ttemp.app", isDirectory: true)
        XCTAssertTrue(ApplicationLocation.isInstalled(bundleURL: app,
                                                      applicationsURL: applicationsURL))
    }

    func testMountedDiskApplicationIsNotInstalled() {
        let app = URL(fileURLWithPath: "/Volumes/Ttemp/Ttemp.app", isDirectory: true)
        XCTAssertFalse(ApplicationLocation.isInstalled(bundleURL: app,
                                                       applicationsURL: applicationsURL))
    }

    func testSimilarDirectoryPrefixIsNotInstalled() {
        let app = URL(fileURLWithPath: "/Applications Backup/Ttemp.app", isDirectory: true)
        XCTAssertFalse(ApplicationLocation.isInstalled(bundleURL: app,
                                                       applicationsURL: applicationsURL))
    }

    func testApplicationsDirectoryItselfIsNotAnAppInstallation() {
        XCTAssertFalse(ApplicationLocation.isInstalled(bundleURL: applicationsURL,
                                                       applicationsURL: applicationsURL))
    }

    func testSymlinkedPathIsJudgedByItsResolvedDestination() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("Ttemp-ApplicationLocation-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let realApplications = root.appendingPathComponent("Applications", isDirectory: true)
        let applicationsLink = root.appendingPathComponent("Applications Link", isDirectory: true)
        try fileManager.createDirectory(at: realApplications, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: realApplications.appendingPathComponent("Ttemp.app", isDirectory: true),
            withIntermediateDirectories: false
        )
        try fileManager.createSymbolicLink(at: applicationsLink, withDestinationURL: realApplications)

        let appThroughLink = applicationsLink.appendingPathComponent("Ttemp.app", isDirectory: true)
        XCTAssertTrue(ApplicationLocation.isInstalled(bundleURL: appThroughLink,
                                                      applicationsURL: realApplications))
    }
}
