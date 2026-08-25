import CoreGraphics
import Foundation

/// ウィンドウの位置とサイズ。`CGRect` を直接 Codable にすると
/// `{"origin":{...},"size":{...}}` になり手で読みにくいため、平坦な形で持つ。
struct FrameSnapshot: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// 永続化されるノート1枚分の状態（SPEC §10.2）。
struct NoteSnapshot: Codable, Equatable {
    var id: UUID
    var content: NoteContent
    var frame: FrameSnapshot
    /// SPEC §10.2: 最前面固定フラグ
    var isPinned: Bool
    /// SPEC §10.2: ウィンドウ個別の文字サイズオフセット（クランプせず生の値を保存する）
    var fontSizeOffset: Double
}

/// `state.json` のルート（SPEC §10.2）。並び順は `notes` の配列順で表す。
struct AppState: Codable, Equatable {
    /// スキーマバージョン。未知のバージョンは読まずに退避する（SPEC §10.4 の方針を流用）。
    static let currentVersion = 1

    var version: Int
    var notes: [NoteSnapshot]

    init(version: Int = AppState.currentVersion, notes: [NoteSnapshot] = []) {
        self.version = version
        self.notes = notes
    }
}
