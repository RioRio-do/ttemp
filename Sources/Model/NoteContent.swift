import CoreGraphics
import Foundation

/// 画像の参照（SPEC §10.2: 原本バイト列は `Images/<uuid>.<ext>` に置き、JSON からは参照のみ）。
struct ImageReference: Codable, Equatable {
    let id: UUID
    /// 原本の拡張子（`png` / `gif` / `heic` など。不明な場合は `dat`）
    let fileExtension: String

    var fileName: String { "\(id.uuidString).\(fileExtension)" }

    init(id: UUID, fileExtension: String) {
        self.id = id
        self.fileExtension = Self.normalizedFileExtension(fileExtension)
    }

    private enum CodingKeys: String, CodingKey {
        case id, fileExtension
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  fileExtension: try container.decode(String.self, forKey: .fileExtension))
    }

    /// 永続化ファイル名の一部として安全に使える、短い ASCII 拡張子へ正規化する。
    ///
    /// `state.json` はユーザーが編集できるため、`../` や区切り文字を含む値を
    /// `Images/` 以下のパスとして解釈してはいけない。不明・不正な値は、元形式での
    /// 書き出しを抑止する `dat` に落とす。
    static func normalizedFileExtension(_ value: String) -> String {
        let candidate = value.lowercased()
        guard (1...16).contains(candidate.utf8.count),
              candidate.utf8.allSatisfy({ byte in
                  (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                      || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
              }) else {
            return "dat"
        }
        return candidate
    }

    /// `ImageStore` が生成する `<UUID>.<ext>` 形式のファイルだけを識別する。
    /// 孤児掃除で `Images/` に偶然置かれた無関係なファイルを消さないために使う。
    static func isManagedFileName(_ name: String) -> Bool {
        guard let separator = name.lastIndex(of: ".") else { return false }
        let idPart = String(name[..<separator])
        let extensionPart = String(name[name.index(after: separator)...])
        return UUID(uuidString: idPart) != nil
            && normalizedFileExtension(extensionPart) == extensionPart
    }
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
