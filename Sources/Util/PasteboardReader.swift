import AppKit
import UniformTypeIdentifiers

/// pasteboard から読み取った内容のスナップショット。
/// `NSPasteboard` に触らずに判定ロジックをテストできるようにするための中間表現。
struct PasteboardSnapshot: Equatable {
    var fileURLs: [URL] = []
    /// プレーンテキスト型が pasteboard に存在するか（SPEC §5.4 の条件2で使う）
    var hasPlainText: Bool = false
    var text: String?
    var imageData: Data?
    var imageFileExtension: String?
}

/// SPEC §5.4 の判定結果。
enum PasteDecision: Equatable {
    case text(String)
    /// pasteboard 上の画像データ
    case image(data: Data, fileExtension: String)
    /// 画像ファイルの URL（バイト列は呼び出し側が読む。原本を保つため。SPEC §6.3）
    case imageFile(URL)
    /// 画像以外のファイルなど、扱えない内容
    case rejectUnsupported
    /// 取り出せるものが何もない
    case none
}

/// SPEC §6.1 のモード遷移を適用した結果。
enum PasteOutcome: Equatable {
    case insertText(String)
    case setImage(PasteDecision)
    /// 拒否フィードバック（シェイク）のみ
    case reject
    /// 何もしない
    case ignore
}

/// ウィンドウの現在のモード（SPEC §6.1 の表の行）。
enum NoteModeState: Equatable {
    case emptyText
    case filledText
    case image
}

enum PasteboardReader {
    /// SPEC §5.4: クリップボードに複数形式が含まれる場合の判定順。
    static func decide(_ snapshot: PasteboardSnapshot) -> PasteDecision {
        // 1. ファイル URL がある場合、pasteboard 上の画像データは見ない。
        //    Finder はファイルコピー時にアイコン画像を載せることがあり、
        //    PDF のコピーがアイコン絵で画像モードになる誤判定を防ぐ。
        if !snapshot.fileURLs.isEmpty {
            // SPEC §6.3: 複数ファイルなら最初の画像ファイル1枚のみ受け付ける
            if let imageURL = snapshot.fileURLs.first(where: { isImageFile($0) }) {
                return .imageFile(imageURL)
            }
            return .rejectUnsupported
        }

        // 2. 画像データがあり、かつプレーンテキスト型が存在しない場合のみ画像とみなす。
        //    「画像＋プレーンテキスト」混在は常にテキストを優先する（SPEC §5.4）。
        if let data = snapshot.imageData, !snapshot.hasPlainText {
            return .image(data: data, fileExtension: snapshot.imageFileExtension ?? "png")
        }

        // 3. それ以外はプレーンテキスト。
        if let text = snapshot.text {
            return .text(text)
        }
        return .none
    }

    /// SPEC §6.1: 判定結果とウィンドウのモードから実際の動作を決める。
    static func resolve(_ decision: PasteDecision, mode: NoteModeState) -> PasteOutcome {
        switch decision {
        case .text(let string):
            // 画像モード中のテキストペーストは拒否（SPEC §6.1）
            return mode == .image ? .reject : .insertText(string)

        case .image, .imageFile:
            switch mode {
            case .emptyText:
                return .setImage(decision)
            case .image:
                // 画像モード中の画像は置き換え（1ウィンドウ1枚を保つ）
                return .setImage(decision)
            case .filledText:
                // 文字が入っているウィンドウへの画像は拒否。テキストは無傷（SPEC §6.1）
                return .reject
            }

        case .rejectUnsupported:
            return .reject

        case .none:
            return .ignore
        }
    }

    /// SPEC §6.3: 画像以外のファイルはすべて無視する。
    static func isImageFile(_ url: URL) -> Bool {
        let extensionString = url.pathExtension.lowercased()
        guard !extensionString.isEmpty,
              let type = UTType(filenameExtension: extensionString) else { return false }
        return type.conforms(to: .image)
    }

    // MARK: - NSPasteboard からの読み取り

    /// 原本の形式を保つため、`NSImage` ではなく生データで受け取る（SPEC §6.3）。
    /// TIFF は macOS が変換して載せることが多いので最後に回す。
    private static let imageTypePriority: [(type: NSPasteboard.PasteboardType, ext: String)] = [
        (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"),
        (NSPasteboard.PasteboardType("public.png"), "png"),
        (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
        (NSPasteboard.PasteboardType("public.heic"), "heic"),
        (NSPasteboard.PasteboardType("public.tiff"), "tiff"),
    ]

    static func snapshot(of pasteboard: NSPasteboard) -> PasteboardSnapshot {
        var snapshot = PasteboardSnapshot()

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            snapshot.fileURLs = urls
        }

        let types = pasteboard.types ?? []
        // 「プレーンテキスト型が存在するか」は厳密にプレーンテキスト型だけで見る。
        // ブラウザの「画像をコピー」は画像データ＋HTML なので、HTML をここに数えると
        // 期待どおり画像モードにならなくなる（SPEC §5.4）。
        snapshot.hasPlainText = types.contains(.string)
        // 属性付きテキストしかない場合も文字列として取り出す（SPEC §5.3）
        snapshot.text = plainText(from: pasteboard)

        for candidate in imageTypePriority where types.contains(candidate.type) {
            if let data = pasteboard.data(forType: candidate.type) {
                snapshot.imageData = data
                snapshot.imageFileExtension = candidate.ext
                break
            }
        }

        return snapshot
    }

    /// SPEC §5.3: 属性を捨てて文字列だけ取り出す。RTF/HTML のみの pasteboard も文字列化する。
    static func plainText(from pasteboard: NSPasteboard) -> String? {
        if let string = pasteboard.string(forType: .string) {
            return string
        }
        let objects = pasteboard.readObjects(forClasses: [NSAttributedString.self], options: nil)
        if let attributed = (objects as? [NSAttributedString])?.first {
            return attributed.string
        }
        return nil
    }

    /// ドラッグ&ドロップ／ペーストで受け付ける型（SPEC §6.3）。
    static let acceptedDragTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .string] + imageTypePriority.map(\.type)
}
