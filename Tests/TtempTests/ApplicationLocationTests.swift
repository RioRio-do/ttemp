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
}
