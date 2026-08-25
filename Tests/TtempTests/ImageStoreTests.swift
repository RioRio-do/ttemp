import AppKit
import ImageIO
import XCTest

/// SPEC §6.4 / §10.2 の画像保管境界のテスト。
final class ImageStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ImageStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TtempImageStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = ImageStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func test_原本バイト列を劣化なく保存して読み戻す() throws {
        let reference = ImageReference(id: UUID(), fileExtension: "PNG")
        let data = Data([0, 1, 2, 3, 255])
        try store.save(data, reference: reference)

        XCTAssertEqual(reference.fileExtension, "png")
        XCTAssertEqual(store.load(reference), data)
        store.remove(reference)
        XCTAssertNil(store.load(reference))
    }

    func test_画像の実データから拡張子を判別する() throws {
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        XCTAssertEqual(ImageStore.fileExtension(of: png), "png")
        XCTAssertEqual(ImageStore.fileExtension(of: Data([0, 1, 2])), "dat")
    }

    func test_小さい画像はファイルバックの表示画像として読める() throws {
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let reference = ImageReference(id: UUID(), fileExtension: "png")
        try store.save(png, reference: reference)

        let image = try XCTUnwrap(ImageStore.displayImage(at: store.url(for: reference)))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }
}
