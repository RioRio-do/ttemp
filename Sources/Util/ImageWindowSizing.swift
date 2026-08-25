import CoreGraphics

/// 画像を貼ったときのウィンドウサイズ計算（SPEC §6.2）。純粋計算としてテストする。
enum ImageWindowSizing {
    /// SPEC §6.2: ウィンドウが操作不能にならないための下限
    static let minContentSize = CGSize(width: 200, height: 150)
    /// SPEC §6.2: ディスプレイの可視領域に対する上限
    static let maxVisibleFraction: CGFloat = 0.6

    /// - Parameter imagePointSize: `NSImage.size`（DPI メタデータを反映した論理サイズ）。
    ///   ピクセル数を渡してはいけない（Retina の 2x スクリーンショットで巨大ウィンドウになる。SPEC §6.2）
    static func contentSize(forImagePointSize imagePointSize: CGSize,
                            visibleFrame: CGRect) -> CGSize {
        guard imagePointSize.width > 0, imagePointSize.height > 0,
              imagePointSize.width.isFinite, imagePointSize.height.isFinite else {
            return minContentSize
        }

        let cap = CGSize(width: visibleFrame.width * maxVisibleFraction,
                         height: visibleFrame.height * maxVisibleFraction)
        // アスペクト比を保ったまま上限に収める（拡大はしない）
        let scale = min(1, min(cap.width / imagePointSize.width, cap.height / imagePointSize.height))
        let scaled = CGSize(width: imagePointSize.width * scale,
                            height: imagePointSize.height * scale)

        // 下限を確保する。画像はこの箱の中央に等倍で表示される（SPEC §6.2）
        return CGSize(width: max(scaled.width, minContentSize.width),
                      height: max(scaled.height, minContentSize.height))
    }
}
