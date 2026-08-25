import CoreGraphics
import Foundation

/// 画像の参照（SPEC §10.2: 原本バイト列は `Images/<uuid>.<ext>` に置き、JSON からは参照のみ）。
struct ImageReference: Codable, Equatable {
    let id: UUID
    /// 原本の拡張子（`png` / `gif` / `heic` など。不明な場合は `dat`）
    let fileExtension: String

    var fileName: String { "\(id.uuidString).\(fileExtension)" }
}

/// ノート1枚の内容（SPEC §5 / §6）。
enum NoteContent: Equatable {
    case text(String)
    case image(ImageReference)

    /// SPEC §3.2: 「空」の定義 — テキストモードで trim して0文字。画像モードは常に空でない。
    var isEmpty: Bool {
        switch self {
        case .text(let string): return PlainTextSanitizer.isEffectivelyEmpty(string)
        case .image: return false
        }
    }
}

extension NoteContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, text, image
    }

    private enum Kind: String, Codable {
        case text, image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(try container.decode(ImageReference.self, forKey: .image))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let string):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(string, forKey: .text)
        case .image(let reference):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(reference, forKey: .image)
        }
    }
}
