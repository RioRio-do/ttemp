import AppKit
import ImageIO
import XCTest

/// SPEC §6.4 / §10.2 の画像保管境界のテスト。
final class ImageStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ImageStore!

    private var onePixelPNG: Data {
        get throws {
            try XCTUnwrap(Data(base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        }
    }

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
        let png = try onePixelPNG
        XCTAssertEqual(ImageStore.fileExtension(of: png), "png")
        XCTAssertEqual(ImageStore.fileExtension(of: Data([0, 1, 2])), "dat")
        XCTAssertEqual(try ImageStore.validatedFileExtension(of: png), "png")
        XCTAssertThrowsError(try ImageStore.validatedFileExtension(of: Data([0, 1, 2])))
    }

    func test_小さい画像はファイルバックの表示画像として読める() throws {
        let png = try onePixelPNG
        let reference = ImageReference(id: UUID(), fileExtension: "png")
        try store.save(png, reference: reference)

        let image = try XCTUnwrap(ImageStore.displayImage(at: store.url(for: reference)))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func test_画像byte上限を読み込み前後で強制する() throws {
        let url = directory.appendingPathComponent("image.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try onePixelPNG.write(to: url)
        let limits = ImageImportLimits(maximumEncodedByteCount: 4,
                                       maximumFrameCount: 100,
                                       maximumTotalPixelCount: 64_000_000)
        XCTAssertThrowsError(try ImageStore.loadImportData(from: url, limits: limits))
    }

    func test_通常ファイル以外は読み込まない() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("original.png")
        let link = directory.appendingPathComponent("link.png")
        try onePixelPNG.write(to: original)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)

        XCTAssertThrowsError(try ImageStore.loadImportData(from: link))
    }

    func test_decode前にframe数と累積pixel数を制限する() throws {
        let png = try onePixelPNG
        let noFramesAllowed = ImageImportLimits(maximumEncodedByteCount: png.count,
                                                maximumFrameCount: 0,
                                                maximumTotalPixelCount: 1)
        XCTAssertThrowsError(try ImageStore.validatedFileExtension(of: png,
                                                                   limits: noFramesAllowed))

        let noPixelsAllowed = ImageImportLimits(maximumEncodedByteCount: png.count,
                                                maximumFrameCount: 1,
                                                maximumTotalPixelCount: 0)
        XCTAssertThrowsError(try ImageStore.validatedFileExtension(of: png,
                                                                   limits: noPixelsAllowed))
    }
}
