import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 「画像を保存」の形式変換とファイル名（SPEC §8.2）。
enum ImageExportFormat: Equatable {
    /// 元の形式のまま（再エンコードしない。GIF アニメーションや HEIC のメタデータを守る）
    case original(fileExtension: String)
    case png
    case jpeg
    case heic
    case tiff

    var displayName: String {
        switch self {
        case .original(let ext): return L10n.pick("元の形式のまま (\(ext.uppercased()))",
                                                  "Original Format (\(ext.uppercased()))")
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .original(let ext): return ext
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        }
    }

    var utType: UTType? {
        switch self {
        case .original: return nil
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return UTType("public.heic")
        case .tiff: return .tiff
        }
    }
}

enum ImageExporter {
    /// SPEC §8.2: JPEG 品質は 0.9 固定（品質スライダーは出さない）
    static let jpegQuality: CGFloat = 0.9

    /// SPEC §8.2: `Ttemp 2026-07-25 21.34.12.png` 形式（スクリーンショットの命名に倣う）
    static func defaultFileName(date: Date, fileExtension: String, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Ttemp \(formatter.string(from: date)).\(fileExtension)"
    }

    /// 指定形式のデータを作る。`original` は原本をそのまま返す（再エンコードしない）。
    static func encode(originalData: Data, to format: ImageExportFormat) -> Data? {
        if case .original = format {
            return originalData
        }
        guard let type = format.utType,
              let source = CGImageSourceCreateWithData(originalData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output,
                                                                type.identifier as CFString,
                                                                1,
                                                                nil) else { return nil }
        var options: [CFString: Any] = [:]
        if format == .jpeg || format == .heic {
            options[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// 保存メニューに並べる形式（SPEC §8.2）。元形式が判別できる場合のみ先頭に足す。
    static func availableFormats(originalExtension: String?) -> [ImageExportFormat] {
        var formats: [ImageExportFormat] = []
        if let originalExtension, originalExtension != "dat" {
            formats.append(.original(fileExtension: originalExtension))
        }
        formats.append(contentsOf: [.png, .jpeg, .heic, .tiff])
        return formats
    }
}
