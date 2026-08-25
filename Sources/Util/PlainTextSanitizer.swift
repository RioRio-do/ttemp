import Foundation

/// ペースト内容のプレーンテキスト化（SPEC §5.3）。
///
/// 属性の除去は「pasteboard から文字列として読む」ことで達成されるため、
/// ここでは残った正規化処理（改行コードの統一）を担う。
/// タブ・全角スペース・絵文字・連続する空行はそのまま保持する。
enum PlainTextSanitizer {
    /// 一時メモとして十分な長さを確保しつつ、貼り付け・復元・TextKit の資源消費を制限する。
    /// UTF-16 単位なのは `NSTextView` / `NSRange` と同じ尺度で、編集ごとの全文走査を避けるため。
    static let maximumUTF16Length = 262_144

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

    static func isWithinStorageLimit(_ text: String) -> Bool {
        (text as NSString).length <= maximumUTF16Length
    }

    /// `NSTextViewDelegate` から通常入力・IME・paste のすべてへ同じ上限を適用する。
    /// 既存本文を複製せず、置換される UTF-16 長と入力部分だけで判定する。
    static func canReplace(currentUTF16Length: Int,
                           range: NSRange,
                           replacement: String?) -> Bool {
        guard range.location >= 0,
              range.length >= 0,
              range.location <= currentUTF16Length,
              range.length <= currentUTF16Length - range.location else { return false }
        let remainingLength = currentUTF16Length - range.length
        let replacementLength = replacement.map { ($0 as NSString).length } ?? 0
        return replacementLength <= maximumUTF16Length - remainingLength
    }
}
