import XCTest

/// SPEC §5.4（ペースト内容の判定順）と §6.1（モード遷移）のテスト。
/// 事故が起きやすい箇所なので分岐を網羅する。
final class PasteboardReaderTests: XCTestCase {
    private let imageData = Data([0x89, 0x50, 0x4E, 0x47])
    private func fileURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    // MARK: - 判定順（SPEC §5.4）

    func test_テキストだけならテキスト() {
        let snapshot = PasteboardSnapshot(hasPlainText: true, text: "hello")
        XCTAssertEqual(PasteboardReader.decide(snapshot), .text("hello"))
    }

    func test_画像データだけなら画像() {
        let snapshot = PasteboardSnapshot(imageData: imageData, imageFileExtension: "png")
        XCTAssertEqual(PasteboardReader.decide(snapshot), .image(data: imageData, fileExtension: "png"))
    }

    func test_画像とプレーンテキストの混在はテキストを優先する() {
        // 意図せず画像モードになって入力不能になる方が事故として大きい（SPEC §5.4）
        let snapshot = PasteboardSnapshot(hasPlainText: true,
                                          text: "説明文",
                                          imageData: imageData,
                                          imageFileExtension: "png")
        XCTAssertEqual(PasteboardReader.decide(snapshot), .text("説明文"))
    }

    func test_ブラウザの画像コピーは画像になる() {
        // 画像データ＋HTML（プレーンテキスト型なし）は画像モード
        let snapshot = PasteboardSnapshot(hasPlainText: false,
                                          text: "<img src=…>",
                                          imageData: imageData,
                                          imageFileExtension: "png")
        XCTAssertEqual(PasteboardReader.decide(snapshot), .image(data: imageData, fileExtension: "png"))
    }

    func test_ファイルURLは画像データより優先される() {
        // Finder はファイルコピー時にアイコン画像を載せることがある（SPEC §5.4）
        let snapshot = PasteboardSnapshot(fileURLs: [fileURL("document.pdf")],
                                          imageData: imageData,
                                          imageFileExtension: "png")
        XCTAssertEqual(PasteboardReader.decide(snapshot), .rejectUnsupported)
    }

    func test_画像ファイルのURLは画像として扱う() {
        let url = fileURL("photo.HEIC")
        let snapshot = PasteboardSnapshot(fileURLs: [url])
        XCTAssertEqual(PasteboardReader.decide(snapshot), .imageFile(url))
    }

    func test_複数ファイルは最初の画像1枚だけ受け付ける() {
        let snapshot = PasteboardSnapshot(fileURLs: [
            fileURL("a.zip"), fileURL("b.png"), fileURL("c.jpg"),
        ])
        XCTAssertEqual(PasteboardReader.decide(snapshot), .imageFile(fileURL("b.png")))
    }

    func test_画像以外のファイルは拒否する() {
        for name in ["a.pdf", "a.txt", "a.zip", "a", "a.swift"] {
            XCTAssertEqual(PasteboardReader.decide(PasteboardSnapshot(fileURLs: [fileURL(name)])),
                           .rejectUnsupported,
                           name)
        }
    }

    func test_何もなければnone() {
        XCTAssertEqual(PasteboardReader.decide(PasteboardSnapshot()), .none)
    }

    func test_拡張子の大文字小文字を問わない() {
        XCTAssertTrue(PasteboardReader.isImageFile(fileURL("A.PNG")))
        XCTAssertTrue(PasteboardReader.isImageFile(fileURL("a.webp")))
        XCTAssertTrue(PasteboardReader.isImageFile(fileURL("a.gif")))
        XCTAssertFalse(PasteboardReader.isImageFile(fileURL("a.pdf")))
    }

    // MARK: - モード遷移（SPEC §6.1）

    func test_空のウィンドウは画像を受け付ける() {
        let decision = PasteDecision.image(data: imageData, fileExtension: "png")
        XCTAssertEqual(PasteboardReader.resolve(decision, mode: .emptyText), .setImage(decision))
    }

    func test_文字が入っているウィンドウへの画像は拒否() {
        let decision = PasteDecision.image(data: imageData, fileExtension: "png")
        XCTAssertEqual(PasteboardReader.resolve(decision, mode: .filledText), .reject)
    }

    func test_画像モード中の画像は置き換え() {
        let decision = PasteDecision.imageFile(fileURL("new.png"))
        XCTAssertEqual(PasteboardReader.resolve(decision, mode: .image), .setImage(decision))
    }

    func test_画像モード中のテキストは拒否() {
        XCTAssertEqual(PasteboardReader.resolve(.text("abc"), mode: .image), .reject)
    }

    func test_テキストモードならテキストを挿入する() {
        XCTAssertEqual(PasteboardReader.resolve(.text("abc"), mode: .emptyText), .insertText("abc"))
        XCTAssertEqual(PasteboardReader.resolve(.text("abc"), mode: .filledText), .insertText("abc"))
    }

    func test_扱えない内容はどのモードでも拒否() {
        for mode in [NoteModeState.emptyText, .filledText, .image] {
            XCTAssertEqual(PasteboardReader.resolve(.rejectUnsupported, mode: mode), .reject)
        }
    }

    func test_取り出せる内容がなければ何もしない() {
        for mode in [NoteModeState.emptyText, .filledText, .image] {
            XCTAssertEqual(PasteboardReader.resolve(.none, mode: mode), .ignore)
        }
    }
}
