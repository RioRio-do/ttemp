import Foundation

/// ペースト内容のプレーンテキスト化（SPEC §5.3）。
///
/// 属性の除去は「pasteboard から文字列として読む」ことで達成されるため、
/// ここでは残った正規化処理（改行コードの統一）を担う。
/// タブ・全角スペース・絵文字・連続する空行はそのまま保持する。
enum PlainTextSanitizer {
    static func sanitize(_ input: String) -> String {
        // SPEC §5.3: 改行コードを LF に統一（CRLF / CR → LF）
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// SPEC §3.2: 「空」の判定。前後の空白・改行を trim して0文字なら空。
    static func isEffectivelyEmpty(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
