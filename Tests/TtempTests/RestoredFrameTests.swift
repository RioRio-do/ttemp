import XCTest

/// SPEC §10.3 の復元位置クランプのテスト。
/// ディスプレイ構成が変わってもウィンドウが操作不能にならないことを保証する。
final class RestoredFrameTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1920, height: 1055)
    private let external = CGRect(x: 1920, y: 0, width: 2560, height: 1415)

    func test_同じ構成なら位置はそのまま() {
        let saved = CGRect(x: 300, y: 200, width: 480, height: 320)
        let frame = WindowPlacement.restoredFrame(saved: saved,
                                                 visibleFrames: [main, external],
                                                 fallback: main)
        XCTAssertEqual(frame, saved)
    }

    func test_外部ディスプレイ上のウィンドウは外すとメインに寄る() {
        let saved = CGRect(x: 2400, y: 900, width: 480, height: 320)
        let frame = WindowPlacement.restoredFrame(saved: saved,
                                                 visibleFrames: [main],
                                                 fallback: main)
        XCTAssertTrue(main.contains(frame), "メインの可視領域に収まること")
        // どの画面にも重なっていなかったので中央に置かれる
        XCTAssertEqual(frame.midX, main.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, main.midY, accuracy: 0.5)
    }

    func test_一部だけ画面外なら重なっている画面内にクランプされる() {
        let saved = CGRect(x: 1800, y: -200, width: 480, height: 320)
        let frame = WindowPlacement.restoredFrame(saved: saved,
                                                 visibleFrames: [main],
                                                 fallback: main)
        XCTAssertTrue(main.contains(frame))
        XCTAssertEqual(frame.maxX, main.maxX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, main.minY, accuracy: 0.5)
        XCTAssertEqual(frame.size, saved.size, "サイズは変えない")
    }

    func test_重なりが大きい画面が選ばれる() {
        let saved = CGRect(x: 1800, y: 100, width: 480, height: 320)   // 大半が外部側
        let frame = WindowPlacement.restoredFrame(saved: saved,
                                                 visibleFrames: [main, external],
                                                 fallback: main)
        XCTAssertTrue(external.contains(frame))
    }

    func test_可視領域より大きいウィンドウは縮められる() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 300)
        let saved = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = WindowPlacement.restoredFrame(saved: saved,
                                                 visibleFrames: [small],
                                                 fallback: small)
        XCTAssertEqual(frame.size, small.size)
        XCTAssertTrue(small.contains(frame))
    }

    func test_画面が1枚もなくてもfallbackに収まる() {
        let saved = CGRect(x: 9999, y: 9999, width: 480, height: 320)
        let frame = WindowPlacement.restoredFrame(saved: saved,
                                                 visibleFrames: [],
                                                 fallback: main)
        XCTAssertTrue(main.contains(frame))
    }

    // MARK: - 壊れた保存値に対する下限

    func test_極端に小さい保存値は下限サイズまで戻される() {
        let saved = CGRect(x: 300, y: 200, width: 0, height: 0)
        let frame = WindowPlacement.restoredFrame(saved: saved,
                                                 visibleFrames: [main],
                                                 fallback: main)
        XCTAssertEqual(frame.size, ImageWindowSizing.minContentSize,
                       "掴めないウィンドウが生まれないこと")
        XCTAssertTrue(main.contains(frame))
    }

    func test_下限より狭い可視領域では可視領域が優先される() {
        let tiny = CGRect(x: 0, y: 0, width: 120, height: 90)
        let saved = CGRect(x: 0, y: 0, width: 10, height: 10)
        let frame = WindowPlacement.restoredFrame(saved: saved,
                                                 visibleFrames: [tiny],
                                                 fallback: tiny)
        XCTAssertEqual(frame.size, tiny.size, "下限より画面が狭ければ画面に収める方を優先する")
    }

    func test_正常な保存値は下限の導入で変わらない() {
        let saved = CGRect(x: 300, y: 200, width: 480, height: 320)
        let frame = WindowPlacement.restoredFrame(saved: saved,
                                                 visibleFrames: [main, external],
                                                 fallback: main)
        XCTAssertEqual(frame, saved)
    }
}
