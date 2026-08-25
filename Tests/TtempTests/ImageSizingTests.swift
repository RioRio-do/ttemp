import ImageIO
import XCTest

/// SPEC §6.2 のウィンドウサイズ計算と §8.2 の保存形式のテスト。
final class ImageSizingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func test_小さい画像は等倍で下限を確保する() {
        let size = ImageWindowSizing.contentSize(forImagePointSize: CGSize(width: 40, height: 30),
                                                 visibleFrame: screen)
        XCTAssertEqual(size, ImageWindowSizing.minContentSize)
    }

    func test_ふつうの画像は等倍で表示される() {
        let size = ImageWindowSizing.contentSize(forImagePointSize: CGSize(width: 800, height: 600),
                                                 visibleFrame: screen)
        XCTAssertEqual(size, CGSize(width: 800, height: 600))
    }

    func test_大きい画像は可視領域の60パーセントに収まる() {
        let size = ImageWindowSizing.contentSize(forImagePointSize: CGSize(width: 4000, height: 3000),
                                                 visibleFrame: screen)
        XCTAssertLessThanOrEqual(size.width, screen.width * 0.6 + 0.5)
        XCTAssertLessThanOrEqual(size.height, screen.height * 0.6 + 0.5)
        // アスペクト比を保つ
        XCTAssertEqual(size.width / size.height, 4000.0 / 3000.0, accuracy: 0.001)
    }

    func test_縦長の画像は高さで律速され幅は下限で止まる() {
        let size = ImageWindowSizing.contentSize(forImagePointSize: CGSize(width: 400, height: 3000),
                                                 visibleFrame: screen)
        XCTAssertEqual(size.height, screen.height * 0.6, accuracy: 0.5)
        // 縮小後の幅は 86pt しかないが、操作不能にならないよう下限まで広げる。
        // 画像はその中でレターボックス表示される（SPEC §6.2）
        XCTAssertEqual(size.width, ImageWindowSizing.minContentSize.width, accuracy: 0.5)
    }

    func test_不正なサイズは下限を返す() {
        XCTAssertEqual(ImageWindowSizing.contentSize(forImagePointSize: .zero, visibleFrame: screen),
                       ImageWindowSizing.minContentSize)
        XCTAssertEqual(ImageWindowSizing.contentSize(forImagePointSize: CGSize(width: -10, height: 10),
                                                     visibleFrame: screen),
                       ImageWindowSizing.minContentSize)
        XCTAssertEqual(ImageWindowSizing.contentSize(forImagePointSize: CGSize(width: CGFloat.nan, height: 10),
                                                     visibleFrame: screen),
                       ImageWindowSizing.minContentSize)
        XCTAssertEqual(ImageWindowSizing.contentSize(forImagePointSize: CGSize(width: 10, height: CGFloat.infinity),
                                                     visibleFrame: screen),
                       ImageWindowSizing.minContentSize)
    }

    // MARK: - 保存（SPEC §8.2）

    func test_デフォルトファイル名はスクリーンショット風() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 2026-07-25 21:34:12 JST
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 25,
                                                      hour: 21, minute: 34, second: 12))!
        XCTAssertEqual(ImageExporter.defaultFileName(date: date, fileExtension: "png", calendar: calendar),
                       "Ttemp 2026-07-25 21.34.12.png")
    }

    func test_元形式が判別できるときだけ元の形式を出す() {
        let withOriginal = ImageExporter.availableFormats(originalExtension: "gif", supportsHEIC: true)
        XCTAssertEqual(withOriginal.first, .original(fileExtension: "gif"))
        XCTAssertEqual(withOriginal.count, 5)

        let withoutOriginal = ImageExporter.availableFormats(originalExtension: nil, supportsHEIC: true)
        XCTAssertEqual(withoutOriginal, [.png, .jpeg, .heic, .tiff])

        // 判別できなかった場合の dat は出さない
        XCTAssertEqual(ImageExporter.availableFormats(originalExtension: "dat", supportsHEIC: true),
                       [.png, .jpeg, .heic, .tiff])
        XCTAssertEqual(ImageExporter.availableFormats(originalExtension: "../../png", supportsHEIC: false),
                       [.png, .jpeg, .tiff])
        XCTAssertEqual(ImageExporter.availableFormats(originalExtension: nil, supportsHEIC: false),
                       [.png, .jpeg, .tiff])
    }

    func test_元の形式のままは再エンコードしない() {
        let original = Data([1, 2, 3, 4])
        XCTAssertEqual(ImageExporter.encode(originalData: original, to: .original(fileExtension: "gif")),
                       original)
    }

    func test_形式ごとの拡張子() {
        XCTAssertEqual(ImageExportFormat.png.fileExtension, "png")
        XCTAssertEqual(ImageExportFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(ImageExportFormat.heic.fileExtension, "heic")
        XCTAssertEqual(ImageExportFormat.tiff.fileExtension, "tiff")
        XCTAssertEqual(ImageExportFormat.original(fileExtension: "webp").fileExtension, "webp")
    }

    func test_実画像を各形式へ変換できる() throws {
        // 1x1 PNG。ファイル入出力を挟まず ImageIO 変換そのものを検証する。
        let source = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        var formats: [ImageExportFormat] = [.png, .jpeg, .tiff]
        if ImageExporter.canEncodeHEIC {
            formats.append(.heic)
        }

        for format in formats {
            let converted = try XCTUnwrap(ImageExporter.encode(originalData: source, to: format),
                                          "\(format) へ変換できること")
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(converted as CFData, nil))
            XCTAssertEqual(CGImageSourceGetCount(imageSource), 1)
            XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, format.utType?.identifier)
        }
        XCTAssertNil(ImageExporter.encode(originalData: Data([0, 1, 2]), to: .png))
    }
}
