import XCTest

/// SPEC §2 の判定ルールのテスト。
final class ShiftChordDetectorTests: XCTestCase {
    private var detector: ShiftChordDetector!

    override func setUp() {
        super.setUp()
        detector = ShiftChordDetector()
    }

    /// 与えた入力列のうち、発火したインデックスを返す
    private func fire(_ inputs: [ShiftChordInput]) -> [Int] {
        inputs.enumerated().compactMap { detector.handle($0.element) ? $0.offset : nil }
    }

    // MARK: - 発火する経路

    func test_左を押してから右を押し両方離すと発火する() {
        let fired = fire([
            .shiftStateChanged(left: true, right: false),
            .shiftStateChanged(left: true, right: true),
            .shiftStateChanged(left: false, right: true),
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertEqual(fired, [3])
    }

    func test_右を押してから左を押しても発火する() {
        let fired = fire([
            .shiftStateChanged(left: false, right: true),
            .shiftStateChanged(left: true, right: true),
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertEqual(fired, [2])
    }

    func test_発火は両方が離された時点で起きる() {
        XCTAssertFalse(detector.handle(.shiftStateChanged(left: true, right: true)))
        XCTAssertFalse(detector.handle(.shiftStateChanged(left: true, right: false)))
        XCTAssertTrue(detector.handle(.shiftStateChanged(left: false, right: false)))
    }

    func test_連続して2回発火できる() {
        let fired = fire([
            .shiftStateChanged(left: true, right: true),
            .shiftStateChanged(left: false, right: false),
            .shiftStateChanged(left: true, right: true),
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertEqual(fired, [1, 3])
    }

    // MARK: - 発火しない経路

    func test_片側だけでは発火しない() {
        let fired = fire([
            .shiftStateChanged(left: true, right: false),
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertTrue(fired.isEmpty)
    }

    func test_シーケンス中に通常キーが押されると発火しない() {
        let fired = fire([
            .shiftStateChanged(left: true, right: false),
            .keyPressed,
            .shiftStateChanged(left: true, right: true),
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertTrue(fired.isEmpty)
    }

    func test_両方押下後に通常キーが押されると発火しない() {
        let fired = fire([
            .shiftStateChanged(left: true, right: true),
            .keyPressed,
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertTrue(fired.isEmpty)
    }

    func test_他の修飾キーが打鍵されると発火しない() {
        let fired = fire([
            .shiftStateChanged(left: true, right: true),
            .otherModifierPressed,
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertTrue(fired.isEmpty)
    }

    func test_マウスボタンが押されると発火しない() {
        let fired = fire([
            .shiftStateChanged(left: true, right: true),
            .mousePressed,
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertTrue(fired.isEmpty)
    }

    /// SPEC §2 細則: 無効化の起点は「最初の Shift 押下」。
    /// 「左 Shift を押しながらタイプ → 右 Shift に触れる → 両方離す」で誤爆しない。
    func test_Shiftを押しながらタイプしてから両押ししても発火しない() {
        let fired = fire([
            .shiftStateChanged(left: true, right: false),
            .keyPressed,
            .shiftStateChanged(left: true, right: true),
            .shiftStateChanged(left: true, right: false),
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertTrue(fired.isEmpty)
    }

    /// SPEC §2 細則: すべての Shift が離されれば次のシーケンスで発火できる。
    func test_無効化されてもすべて離せば次は発火する() {
        let fired = fire([
            .shiftStateChanged(left: true, right: false),
            .keyPressed,
            .shiftStateChanged(left: false, right: false),   // 無効化を解除
            .shiftStateChanged(left: true, right: true),
            .shiftStateChanged(left: false, right: false),   // ここで発火
        ])
        XCTAssertEqual(fired, [4])
    }

    /// 無効化中に Shift を押し直しても、いったん全部離すまでは発火しない。
    func test_無効化中に押し直しても発火しない() {
        let fired = fire([
            .shiftStateChanged(left: true, right: false),
            .keyPressed,
            .shiftStateChanged(left: true, right: true),
            .shiftStateChanged(left: false, right: true),
            .shiftStateChanged(left: true, right: true),
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertTrue(fired.isEmpty)
    }

    /// Shift が押されていない間の入力はシーケンスに影響しない。
    func test_待機中の通常キーは次のシーケンスに影響しない() {
        let fired = fire([
            .keyPressed,
            .mousePressed,
            .otherModifierPressed,
            .shiftStateChanged(left: true, right: true),
            .shiftStateChanged(left: false, right: false),
        ])
        XCTAssertEqual(fired, [4])
    }

    func test_resetでシーケンスが破棄される() {
        detector.handle(.shiftStateChanged(left: true, right: true))
        detector.reset()
        XCTAssertFalse(detector.handle(.shiftStateChanged(left: false, right: false)))
    }
}
