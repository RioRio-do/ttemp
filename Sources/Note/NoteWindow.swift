import AppKit

/// ウィンドウ単位のショートカット処理（SPEC §7.2）。
protocol NoteShortcutHandling: AnyObject {
    /// - Returns: 消費したか
    func handleKeyEquivalent(_ event: NSEvent) -> Bool
}

/// ノート1枚分の `NSWindow`（SPEC §3.5）。
final class NoteWindow: NSWindow {
    weak var shortcutHandler: NoteShortcutHandling?

    /// シェイク中の基準位置。進行中の `frame.origin` を基準にすると流れていくため保持する
    private var shakeBaseOrigin: NSPoint?
    /// 連続シェイクで、古いアニメーションの完了ハンドラが新しい方の後始末をしないための世代番号
    private var shakeGeneration = 0

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // SPEC §3.5: タイトルバーは透明・タイトル文字は出さない
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // SPEC §3.5: 背景ドラッグでも移動できる
        isMovableByWindowBackground = true
        // SPEC §3.5: 背景は不透明。ライト／ダークに自動追従
        isOpaque = true
        backgroundColor = .textBackgroundColor
        hasShadow = true
        // SPEC §3.5: 最小化・ズームは無効（Dock アイコンがないため最小化すると復帰不能）
        standardWindowButton(.miniaturizeButton)?.isEnabled = false
        standardWindowButton(.zoomButton)?.isEnabled = false
        // SPEC §3.3: 開いた Space に固定する（.canJoinAllSpaces は付けない）
        collectionBehavior = [.managed]
        // NSWindow のデフォルトは true。close() でウィンドウ自身が release され、
        // NoteWindowController の強参照と二重解放になってクラッシュする。
        isReleasedWhenClosed = false
        // 復元は state.json で自前に行う（SPEC §10）
        isRestorable = false
        animationBehavior = .none
        // SPEC §3.5 の下限。復元時のクランプ（WindowPlacement）と同じ値を使う
        minSize = ImageWindowSizing.minContentSize
        tabbingMode = .disallowed
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // SPEC §7.2 の文字サイズ操作を先に見る。mainMenu 側と衝突するキーはない。
        if shortcutHandler?.handleKeyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - フェード（SPEC §3.7）

    /// フェードインの開始状態にする。`isOpaque` を落としてから alpha を下げるのが要点。
    func prepareForFadeIn() {
        isOpaque = false
        alphaValue = 0
    }

    /// `alphaValue` を動かす。`isOpaque == true` のまま alpha < 1 にすると、ウィンドウ
    /// サーバは「中身は完全不透明」と信じて背後との合成を省くため、フェード中の描画が
    /// 壊れて残像になる。アニメーションの前後で不透明フラグを正しく切り替える。
    func fade(to alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        isOpaque = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            animator().alphaValue = alpha
        }, completionHandler: { [weak self] in
            // `alphaValue` も見るのは、フェードインの完了が後発のフェードアウトを
            // 追い越したときに不透明へ戻してしまわないため
            if let self, alpha >= 1, self.alphaValue >= 1 {
                self.isOpaque = true
                // 不透明に戻すと影の形状の前提が変わる。明示的に作り直す
                self.invalidateShadow()
            }
            completion?()
        })
    }

    // MARK: - 拒否フィードバック

    /// SPEC §6.1: 拒否フィードバック。ウィンドウを軽く横に揺らす。
    /// 振幅・回数・時間は SPEC §14 の未決事項に対する決定値。
    func shake() {
        let amplitude: CGFloat = 8
        let duration: TimeInterval = 0.24
        // 進行中のシェイクで振れている最中の frame.origin を基準にすると、
        // 拒否を連打するたびに基準がずれてウィンドウが横に流れていく。
        let origin = shakeBaseOrigin ?? frame.origin
        shakeBaseOrigin = origin
        shakeGeneration += 1
        let generation = shakeGeneration

        let offsets: [CGFloat] = [0, -amplitude, amplitude, -amplitude * 0.6, amplitude * 0.6, 0]
        let animation = CAKeyframeAnimation(keyPath: "frameOrigin")
        animation.values = offsets.map { NSValue(point: CGPoint(x: origin.x + $0, y: origin.y)) }
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        animations = ["frameOrigin": animation]
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            animator().setFrameOrigin(origin)
        }, completionHandler: { [weak self] in
            guard let self, self.shakeGeneration == generation else { return }
            // 張りっぱなしにすると、以後 animator() 経由で動かすものがすべて揺れる
            self.animations = [:]
            self.shakeBaseOrigin = nil
            // キーフレームの終端で確実に元の位置へ戻す
            self.setFrameOrigin(origin)
        })
    }
}
