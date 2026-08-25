import CoreGraphics

/// 文字サイズの計算モデル（SPEC §7.1）。
///
/// 各ウィンドウはグローバル値からの相対オフセットを持ち、
/// 実効サイズ = clamp(グローバル値 + オフセット, 9pt, 48pt)。
/// **クランプは表示時のみ適用し、オフセット値自体は保持する。**
enum FontSizeModel {
    static let minSize: CGFloat = 9
    static let maxSize: CGFloat = 48
    static let defaultGlobalSize: CGFloat = 14
    static let step: CGFloat = 1

    /// 表示に使う実効サイズ。
    static func effectiveSize(global: CGFloat, offset: CGFloat) -> CGFloat {
        min(max(global + offset, minSize), maxSize)
    }

    /// SPEC §7.1: グローバル値自体は 9〜48pt にクランプして保持する。
    static func clampGlobal(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultGlobalSize }
        return min(max(value, minSize), maxSize)
    }

    /// グローバル値を1ステップ動かす。
    static func bumpGlobal(_ value: CGFloat, direction: Int) -> CGFloat {
        clampGlobal(value + CGFloat(direction) * step)
    }

    /// オフセットを1ステップ動かす。
    /// オフセットはクランプしない（上限に張り付いた後にグローバル値を下げれば相対関係が復活する）。
    static func bumpOffset(_ offset: CGFloat, direction: Int) -> CGFloat {
        guard offset.isFinite else { return 0 }
        return offset + CGFloat(direction) * step
    }
}
