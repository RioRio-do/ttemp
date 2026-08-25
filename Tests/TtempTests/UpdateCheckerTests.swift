import XCTest

final class UpdateCheckerTests: XCTestCase {
    // MARK: - バージョン比較

    func testNewerPatchVersion() {
        XCTAssertTrue(UpdateChecker.isNewer("v0.1.1", than: "0.1.0"))
    }

    func testNewerMinorVersion() {
        XCTAssertTrue(UpdateChecker.isNewer("v0.2.0", than: "0.1.9"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("v0.1.0", than: "0.1.0"))
    }

    func testOlderVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("v0.1.0", than: "0.2.0"))
    }

    func testMissingComponentsAreTreatedAsZero() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0"))
    }

    func testPreReleaseSuffixIsIgnoredNumerically() {
        // "0-beta" のような要素は数字部分だけを読む
        XCTAssertTrue(UpdateChecker.isNewer("v1.0.1-beta", than: "1.0.0"))
    }

    // MARK: - レスポンス解釈

    private func httpResponse(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: AppInfo.latestReleaseAPIURL,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: nil)!
    }

    func testParseUpdateAvailable() {
        let json = #"{"tag_name": "v9.9.9", "html_url": "https://example.com/release"}"#
        let result = UpdateChecker.parseResponse(data: Data(json.utf8),
                                                 response: httpResponse(status: 200),
                                                 error: nil,
                                                 currentVersion: "0.1.0")
        XCTAssertEqual(result, .updateAvailable(latest: "v9.9.9",
                                                url: URL(string: "https://example.com/release")!))
    }

    func testParseUpToDate() {
        let json = #"{"tag_name": "v0.1.0", "html_url": "https://example.com/release"}"#
        let result = UpdateChecker.parseResponse(data: Data(json.utf8),
                                                 response: httpResponse(status: 200),
                                                 error: nil,
                                                 currentVersion: "0.1.0")
        XCTAssertEqual(result, .upToDate(current: "0.1.0"))
    }

    func testParseHTTPErrorIsFailure() {
        // リリース未作成のリポジトリは 404 を返す
        let result = UpdateChecker.parseResponse(data: nil,
                                                 response: httpResponse(status: 404),
                                                 error: nil,
                                                 currentVersion: "0.1.0")
        XCTAssertEqual(result, .failed("HTTP 404"))
    }

    func testParseBrokenJSONIsFailure() {
        let result = UpdateChecker.parseResponse(data: Data("not json".utf8),
                                                 response: httpResponse(status: 200),
                                                 error: nil,
                                                 currentVersion: "0.1.0")
        XCTAssertEqual(result, .failed("unexpected response"))
    }
}
