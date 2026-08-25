import XCTest

/// SPEC §5.3 の書式剥がし・正規化のテスト。
final class PlainTextSanitizerTests: XCTestCase {
    func test_CRLFはLFに正規化される() {
        XCTAssertEqual(PlainTextSanitizer.sanitize("a\r\nb"), "a\nb")
    }

    func test_単独のCRもLFに正規化される() {
        XCTAssertEqual(PlainTextSanitizer.sanitize("a\rb"), "a\nb")
    }

    func test_タブは保持される() {
        XCTAssertEqual(PlainTextSanitizer.sanitize("a\tb"), "a\tb")
    }

    func test_連続する空行は保持される() {
        XCTAssertEqual(PlainTextSanitizer.sanitize("a\r\n\r\n\r\nb"), "a\n\n\nb")
    }

    func test_全角スペースと絵文字は保持される() {
        XCTAssertEqual(PlainTextSanitizer.sanitize("あ　い🍣"), "あ　い🍣")
    }

    // SPEC §3.2: 「空」の判定
    func test_空文字は空とみなす() {
        XCTAssertTrue(PlainTextSanitizer.isEffectivelyEmpty(""))
    }

    func test_スペースだけは空とみなす() {
        XCTAssertTrue(PlainTextSanitizer.isEffectivelyEmpty("   "))
    }

    func test_改行だけは空とみなす() {
        XCTAssertTrue(PlainTextSanitizer.isEffectivelyEmpty("\n\n"))
    }

    func test_全角スペースだけは空とみなす() {
        XCTAssertTrue(PlainTextSanitizer.isEffectivelyEmpty("　"))
    }

    func test_文字が1つでもあれば空ではない() {
        XCTAssertFalse(PlainTextSanitizer.isEffectivelyEmpty("  a  "))
    }
}
