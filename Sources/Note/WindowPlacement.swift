import CoreGraphics

/// 新規ウィンドウの出現位置とサイズ（SPEC §3.6）。
///
/// 画面情報に依存しない純粋計算として切り出し、テスト対象にする（SPEC §13）。
enum WindowPlacement {
    /// SPEC §3.6: デフォルトサイズは常に固定 480×320
    static let defaultSize = CGSize(width: 480, height: 320)
    /// SPEC §3.6: 重なり回避のカスケード量
    static let cascadeStep: CGFloat = 24
    /// 中央よりどれだけ上に出すか（可視領域の高さに対する比率）
    static let upwardBias: CGFloat = 0.08

    /// 可視領域の「中央やや上」を基準に、既存ウィンドウと重なる場合は右下へカスケードした frame を返す。
    ///
    /// - Parameters:
    ///   - occupiedOrigins: 既存ウィンドウの原点（Cocoa 座標＝左下原点、Y 上向き）
    static func frame(size: CGSize = defaultSize,
                      in visibleFrame: CGRect,
                      occupiedOrigins: [CGPoint]) -> CGRect {
        let base = baseOrigin(size: size, in: visibleFrame)
        var candidate = base
        var wrapCount = 0
        var iterations = 0

        while collides(candidate, with: occupiedOrigins), iterations < 200 {
            candidate.x += cascadeStep
            candidate.y -= cascadeStep

            let overflowsRight = candidate.x + size.width > visibleFrame.maxX
            let overflowsBottom = candidate.y < visibleFrame.minY
            if overflowsRight || overflowsBottom {
                // SPEC §3.6: 画面端に達したら折り返す。
                // 折り返し位置を少しずつずらして同じ地点を巡回しないようにする。
                wrapCount += 1
                candidate = CGPoint(
                    x: visibleFrame.minX + cascadeStep + CGFloat(wrapCount) * 8,
                    y: visibleFrame.maxY - size.height - cascadeStep - CGFloat(wrapCount) * 8
                )
            }
            iterations += 1
        }

        return CGRect(origin: clamp(candidate, size: size, in: visibleFrame), size: size)
    }

    /// 可視領域の中央やや上に置いたときの原点。
    static func baseOrigin(size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2 + visibleFrame.height * upwardBias
        )
        return clamp(origin, size: size, in: visibleFrame)
    }

    /// SPEC §10.3: 保存された frame を現在のディスプレイ構成に合わせて復元する。
    ///
    /// 外部ディスプレイを外した状態で起動しても、ウィンドウが画面外＝操作不能にならないようにする。
    /// - Parameters:
    ///   - visibleFrames: 現在接続されている全ディスプレイの可視領域
    ///   - fallback: いずれの画面にも収まらない場合に中央配置する領域（メインディスプレイ）
    static func restoredFrame(saved: CGRect, visibleFrames: [CGRect], fallback: CGRect) -> CGRect {
        let overlapping = visibleFrames
            .map { (frame: $0, area: $0.intersection(saved).isNull ? 0 : $0.intersection(saved).width * $0.intersection(saved).height) }
            .filter { $0.area > 0 }
            .max { $0.area < $1.area }?
            .frame

        guard let target = overlapping else {
            // どの画面にも重なっていない → メインディスプレイの中央に置く
            let size = fittedSize(saved.size, in: fallback)
            let origin = CGPoint(x: fallback.midX - size.width / 2, y: fallback.midY - size.height / 2)
            return CGRect(origin: clamp(origin, size: size, in: fallback), size: size)
        }

        let size = fittedSize(saved.size, in: target)
        return CGRect(origin: clamp(saved.origin, size: size, in: target), size: size)
    }

    /// 可視領域より大きいサイズは可視領域まで縮め、下限（SPEC §3.5 の 200×150）は必ず確保する。
    ///
    /// 下限を敷くのは、`state.json` が壊れて 0 や極端に小さい値になっていても
    /// 「見えない／掴めないウィンドウ」が生まれないようにするため。JSON のデコードが
    /// 通ってしまう値（NaN ではないが不正なサイズ）はここでしか止められない。
    private static func fittedSize(_ size: CGSize, in visibleFrame: CGRect) -> CGSize {
        let minimum = ImageWindowSizing.minContentSize
        // 可視領域が下限より狭い異常な構成では、可視領域に収める方を優先する
        return CGSize(width: min(max(size.width, minimum.width), visibleFrame.width),
                      height: min(max(size.height, minimum.height), visibleFrame.height))
    }

    /// 原点をウィンドウ全体が可視領域に収まる位置へ丸める（SPEC §10.3 の復元クランプでも使う）。
    static func clamp(_ origin: CGPoint, size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        let maxX = visibleFrame.maxX - size.width
        let maxY = visibleFrame.maxY - size.height
        return CGPoint(
            x: maxX >= visibleFrame.minX ? min(max(origin.x, visibleFrame.minX), maxX) : visibleFrame.minX,
            y: maxY >= visibleFrame.minY ? min(max(origin.y, visibleFrame.minY), maxY) : visibleFrame.minY
        )
    }

    private static func collides(_ candidate: CGPoint, with origins: [CGPoint]) -> Bool {
        origins.contains { abs($0.x - candidate.x) < 1 && abs($0.y - candidate.y) < 1 }
    }
}
