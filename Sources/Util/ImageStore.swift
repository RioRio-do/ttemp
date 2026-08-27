import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ImageImportLimits: Equatable {
    let maximumEncodedByteCount: Int
    let maximumFrameCount: Int
    let maximumTotalPixelCount: Int64
}

/// 画像の保存・読込・ダウンサンプリング（SPEC §6.4 / §10.2）。
///
/// 原本のバイト列を必ず保持し（「元の形式のまま保存」「画像をコピー」で劣化させないため）、
/// 表示用の `NSImage` は必要に応じて縮小して別に作る。
final class ImageStore {
    /// 表示用ダウンサンプリングの閾値（SPEC §6.4）。
    /// 4K ディスプレイの物理ピクセルを十分に上回るため、これ以上の解像度は表示に寄与しない。
    static let displayMaxPixelSize: CGFloat = 4096
    static let defaultImportLimits = ImageImportLimits(maximumEncodedByteCount: 64 * 1_024 * 1_024,
                                                       maximumFrameCount: 100,
                                                       maximumTotalPixelCount: 64_000_000)

    enum ImportError: Error {
        case notRegularFile
        case encodedDataTooLarge
        case unsupportedImage
        case tooManyFrames
        case pixelBudgetExceeded
    }

    private let directory: URL
    private let fileManager: FileManager
    private let pendingImports: PendingImageImports?

    init(directory: URL, fileManager: FileManager = .default, pendingImports: PendingImageImports? = nil) {
        self.directory = directory
        self.fileManager = fileManager
        self.pendingImports = pendingImports
    }

    func url(for reference: ImageReference) -> URL {
        directory.appendingPathComponent(reference.fileName)
    }

    /// SPEC §10.2: 原本のバイト列を `Images/<uuid>.<ext>` に保存する。
    func save(_ data: Data, reference: ImageReference) throws {
        guard data.count <= Self.defaultImportLimits.maximumEncodedByteCount else {
            throw ImportError.encodedDataTooLarge
        }
        pendingImports?.protect(reference)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: reference), options: .atomic)
        } catch {
            pendingImports?.release(reference)
            throw error
        }
    }

    func load(_ reference: ImageReference) -> Data? {
        try? Self.loadBoundedData(from: url(for: reference),
                                  limits: Self.defaultImportLimits)
    }

    /// Open while the window still owns the image. The handle keeps the original
    /// inode readable even if a later close/replacement lets state GC unlink it.
    /// Opening is cheap; the bounded read and encoding remain on the worker queue.
    func openOriginal(_ reference: ImageReference) throws -> FileHandle {
        let originalURL = url(for: reference)
        try Self.validateRegularFile(at: originalURL, limits: Self.defaultImportLimits)
        return try FileHandle(forReadingFrom: originalURL)
    }

    /// Consumes and closes the handle, including on read/size-limit failure.
    static func readOriginal(from handle: FileHandle) throws -> Data {
        defer { try? handle.close() }
        let limit = defaultImportLimits.maximumEncodedByteCount
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ImportError.encodedDataTooLarge }
        return data
    }

    func remove(_ reference: ImageReference) {
        try? fileManager.removeItem(at: url(for: reference))
        pendingImports?.release(reference)
    }

    func didInstall(_ reference: ImageReference) {
        pendingImports?.didInstall(reference)
    }

    // MARK: - 表示用画像

    /// 保存済みファイルから表示用の `NSImage` を作る。巨大画像はダウンサンプリングする（SPEC §6.4）。
    /// GIF アニメーションはフレームを保つ必要があるため縮小しない。
    ///
    /// `Data` からではなくファイルから作るのは意図的: `NSImage(data:)` は圧縮バイト列を
    /// ノートの生存中ずっとヒープに保持するが、ファイルバックならメモリ圧時に破棄・再読込できる。
    static func displayImage(at url: URL,
                             limits: ImageImportLimits = defaultImportLimits) -> NSImage? {
        do {
            try validateRegularFile(at: url, limits: limits)
        } catch {
            return nil
        }

        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
              (try? validate(source: source, limits: limits)) != nil else { return nil }

        // ダウンサンプリング不要な場合は原寸のファイルバック画像にする。
        let fullImage = { NSImage(contentsOf: url) }
        guard !isAnimated(source) else {
            return fullImage()
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = CGFloat((properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0)
        let pixelHeight = CGFloat((properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0)
        guard max(pixelWidth, pixelHeight) > displayMaxPixelSize else {
            return fullImage()
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: displayMaxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        // 論理サイズ（pt）は原本のまま保つ。縮小したのはあくまで表示用の解像度（SPEC §6.2）。
        // NSImage の size は DPI メタデータを反映した論理サイズを返す
        if let full = fullImage(), full.size.width > 0, full.size.height > 0 {
            return NSImage(cgImage: thumbnail, size: full.size)
        }
        return NSImage(cgImage: thumbnail,
                       size: CGSize(width: thumbnail.width, height: thumbnail.height))
    }

    private static func isAnimated(_ source: CGImageSource) -> Bool {
        guard CGImageSourceGetCount(source) > 1 else { return false }
        guard let type = CGImageSourceGetType(source) as String? else { return false }
        // GIF / APNG / WebP のように複数フレームを持つ形式
        return type == UTType.gif.identifier
            || type == UTType.png.identifier
            || type == UTType.webP.identifier
    }

    /// file URL は通常ファイルかつ上限内であることを確認してから読む。
    /// FIFO / device などへ `Data(contentsOf:)` して background worker が永久待ちになるのを防ぐ。
    static func loadImportData(from url: URL,
                               limits: ImageImportLimits = defaultImportLimits) throws -> Data {
        let data = try loadBoundedData(from: url, limits: limits)
        _ = try validatedFileExtension(of: data, limits: limits)
        return data
    }

    private static func loadBoundedData(from url: URL,
                                        limits: ImageImportLimits) throws -> Data {
        try validateRegularFile(at: url, limits: limits)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= limits.maximumEncodedByteCount else {
            throw ImportError.encodedDataTooLarge
        }
        return data
    }

    private static func validateRegularFile(at url: URL,
                                            limits: ImageImportLimits) throws {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ImportError.notRegularFile
        }
        guard let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= limits.maximumEncodedByteCount else {
            throw ImportError.encodedDataTooLarge
        }
    }

    /// ImageIO のメタデータだけを読み、decode 前に frame 数と累積 pixel 数を制限する。
    static func validatedFileExtension(of data: Data,
                                       limits: ImageImportLimits = defaultImportLimits) throws -> String {
        guard !data.isEmpty, data.count <= limits.maximumEncodedByteCount else {
            throw ImportError.encodedDataTooLarge
        }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier),
              type.conforms(to: .image) else { throw ImportError.unsupportedImage }
        try validate(source: source, limits: limits)
        return type.preferredFilenameExtension ?? "dat"
    }

    private static func validate(source: CGImageSource,
                                 limits: ImageImportLimits) throws {
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw ImportError.unsupportedImage }
        guard frameCount <= limits.maximumFrameCount else { throw ImportError.tooManyFrames }

        var totalPixels: Int64 = 0
        for index in 0..<frameCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any],
                let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
                let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
                width > 0,
                height > 0 else { throw ImportError.unsupportedImage }
            let (pixels, multiplicationOverflow) = width.multipliedReportingOverflow(by: height)
            let (nextTotal, additionOverflow) = totalPixels.addingReportingOverflow(pixels)
            guard !multiplicationOverflow,
                  !additionOverflow,
                  pixels <= limits.maximumTotalPixelCount,
                  nextTotal <= limits.maximumTotalPixelCount else {
                throw ImportError.pixelBudgetExceeded
            }
            totalPixels = nextTotal
        }
    }

    /// 原本データから拡張子を推定する。判別できない場合は `dat`。
    static func fileExtension(of data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier),
              let preferred = type.preferredFilenameExtension else { return "dat" }
        return preferred
    }
}
