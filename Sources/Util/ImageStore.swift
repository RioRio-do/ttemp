import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 画像の保存・読込・ダウンサンプリング（SPEC §6.4 / §10.2）。
///
/// 原本のバイト列を必ず保持し（「元の形式のまま保存」「画像をコピー」で劣化させないため）、
/// 表示用の `NSImage` は必要に応じて縮小して別に作る。
final class ImageStore {
    /// 表示用ダウンサンプリングの閾値（SPEC §6.4）。
    /// 4K ディスプレイの物理ピクセルを十分に上回るため、これ以上の解像度は表示に寄与しない。
    static let displayMaxPixelSize: CGFloat = 4096

    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func url(for reference: ImageReference) -> URL {
        directory.appendingPathComponent(reference.fileName)
    }

    /// SPEC §10.2: 原本のバイト列を `Images/<uuid>.<ext>` に保存する。
    func save(_ data: Data, reference: ImageReference) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: reference), options: .atomic)
    }

    func load(_ reference: ImageReference) -> Data? {
        try? Data(contentsOf: url(for: reference), options: .mappedIfSafe)
    }

    func remove(_ reference: ImageReference) {
        try? fileManager.removeItem(at: url(for: reference))
    }

    // MARK: - 表示用画像

    /// 保存済みファイルから表示用の `NSImage` を作る。巨大画像はダウンサンプリングする（SPEC §6.4）。
    /// GIF アニメーションはフレームを保つ必要があるため縮小しない。
    ///
    /// `Data` からではなくファイルから作るのは意図的: `NSImage(data:)` は圧縮バイト列を
    /// ノートの生存中ずっとヒープに保持するが、ファイルバックならメモリ圧時に破棄・再読込できる。
    static func displayImage(at url: URL) -> NSImage? {
        // ダウンサンプリング不要／不能な場合は原寸のファイルバック画像にする
        let fullImage = { NSImage(contentsOf: url) }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), !isAnimated(source) else {
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
            return fullImage()
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

    /// 原本データから拡張子を推定する。判別できない場合は `dat`。
    static func fileExtension(of data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier),
              let preferred = type.preferredFilenameExtension else { return "dat" }
        return preferred
    }
}
