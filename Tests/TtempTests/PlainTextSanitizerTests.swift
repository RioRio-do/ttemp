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

    // SPEC §5.1: TextKit と永続化を守る本文上限
    func test_本文上限の境界を判定できる() {
        let accepted = String(repeating: "a", count: PlainTextSanitizer.maximumUTF16Length)
        XCTAssertTrue(PlainTextSanitizer.isWithinStorageLimit(accepted))
        XCTAssertFalse(PlainTextSanitizer.isWithinStorageLimit(accepted + "a"))
    }

    func test_置換後のUTF16長が上限以内なら受け付ける() {
        XCTAssertTrue(PlainTextSanitizer.canReplace(
            currentUTF16Length: PlainTextSanitizer.maximumUTF16Length,
            range: NSRange(location: PlainTextSanitizer.maximumUTF16Length - 1, length: 1),
            replacement: "b"))
        XCTAssertFalse(PlainTextSanitizer.canReplace(
            currentUTF16Length: PlainTextSanitizer.maximumUTF16Length,
            range: NSRange(location: PlainTextSanitizer.maximumUTF16Length, length: 0),
            replacement: "a"))
    }

    func test_不正な置換範囲は拒否する() {
        XCTAssertFalse(PlainTextSanitizer.canReplace(currentUTF16Length: 3,
                                                     range: NSRange(location: 4, length: 0),
                                                     replacement: "a"))
    }
}
