import Foundation

/// 左右 Shift 同時押しの判定（SPEC §2）。
///
/// 純粋なステートマシンとして実装し、`CGEventTap` から切り離してテストできるようにする。
/// 入力は `EventTapController` が `CGEvent` を意味付けして渡す。
enum ShiftChordInput: Equatable {
    /// 左右 Shift の押下状態が変化した（`flagsChanged` のデバイス依存ビットから算出）
    case shiftStateChanged(left: Bool, right: Bool)
    /// 通常キーが押された（`keyDown`）
    case keyPressed
    /// Shift 以外の修飾キーが打鍵された（⌘ ⌥ ⌃ CapsLock Fn）
    case otherModifierPressed
    /// マウスボタンが押された（左・右・中）
    case mousePressed
}

final class ShiftChordDetector {
    private enum Phase {
        /// Shift が1つも押されていない待機状態
        case idle
        /// シーケンス進行中（最初の Shift 押下から）
        case tracking
        /// シーケンスが無効化された。すべての Shift が離されるまで再判定しない
        case invalidated
    }

    private var phase: Phase = .idle
    private var sawLeft = false
    private var sawRight = false

    /// 1イベントを与える。戻り値 `true` が発火（新規ウィンドウ生成）を意味する。
    @discardableResult
    func handle(_ input: ShiftChordInput) -> Bool {
        switch input {
        case .shiftStateChanged(let left, let right):
            return handleShiftState(left: left, right: right)

        case .keyPressed, .otherModifierPressed, .mousePressed:
            // SPEC §2 条件2〜4: シーケンス中に他の入力があれば無効化する。
            // 起点は「両方が押下状態になった時点」ではなく「最初の Shift 押下」。
            if phase == .tracking {
                phase = .invalidated
            }
            return false
        }
    }

    /// 状態をすべて捨てる（イベントタップの停止・再開時など）。
    func reset() {
        phase = .idle
        sawLeft = false
        sawRight = false
    }

    private func handleShiftState(left: Bool, right: Bool) -> Bool {
        let anyPressed = left || right

        switch phase {
        case .idle:
            guard anyPressed else { return false }
            // SPEC §2: Shift が1つも押されていない状態からの押下でシーケンス開始
            phase = .tracking
            sawLeft = left
            sawRight = right
            return false

        case .tracking:
            sawLeft = sawLeft || left
            sawRight = sawRight || right
            guard !anyPressed else { return false }
            // 条件5: 両方の Shift が離された
            let fired = sawLeft && sawRight
            reset()
            return fired

        case .invalidated:
            if !anyPressed {
                reset()
            }
            return false
        }
    }
}
