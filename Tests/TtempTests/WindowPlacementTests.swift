import XCTest

/// SPEC §3.6 の出現位置とカスケード計算のテスト。
final class WindowPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let size = WindowPlacement.defaultSize

    func test_デフォルトサイズは480x320() {
        XCTAssertEqual(size, CGSize(width: 480, height: 320))
    }

    func test_重なりがなければ中央やや上に置かれる() {
        let frame = WindowPlacement.frame(in: screen, occupiedOrigins: [])
        XCTAssertEqual(frame.size, size)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        // Cocoa 座標は Y 上向き。中央より上＝ midY が大きい
        XCTAssertGreaterThan(frame.midY, screen.midY)
    }

    func test_既存ウィンドウと重なると右下にカスケードする() {
        let base = WindowPlacement.baseOrigin(size: size, in: screen)
        let frame = WindowPlacement.frame(in: screen, occupiedOrigins: [base])
        XCTAssertEqual(frame.origin.x, base.x + WindowPlacement.cascadeStep, accuracy: 0.5)
        XCTAssertEqual(frame.origin.y, base.y - WindowPlacement.cascadeStep, accuracy: 0.5)
    }

    func test_カスケードは空いた位置まで繰り返す() {
        let base = WindowPlacement.baseOrigin(size: size, in: screen)
        let occupied = (0..<3).map {
            CGPoint(x: base.x + CGFloat($0) * WindowPlacement.cascadeStep,
                    y: base.y - CGFloat($0) * WindowPlacement.cascadeStep)
        }
        let frame = WindowPlacement.frame(in: screen, occupiedOrigins: occupied)
        XCTAssertEqual(frame.origin.x, base.x + 3 * WindowPlacement.cascadeStep, accuracy: 0.5)
        XCTAssertEqual(frame.origin.y, base.y - 3 * WindowPlacement.cascadeStep, accuracy: 0.5)
    }

    func test_画面端に達したら折り返す() {
        // 右下ぎりぎりを埋めて、カスケード先が画面外になる状況を作る
        let occupiedOrigin = CGPoint(x: screen.maxX - size.width - 10, y: screen.minY + 10)
        let narrow = CGRect(x: occupiedOrigin.x, y: occupiedOrigin.y,
                            width: size.width + 10, height: size.height + 10)
        let frame = WindowPlacement.frame(in: narrow, occupiedOrigins: [
            WindowPlacement.baseOrigin(size: size, in: narrow)
        ])
        XCTAssertTrue(narrow.contains(frame), "折り返し後も可視領域内に収まること")
    }

    func test_出現位置は常に可視領域内に収まる() {
        let frame = WindowPlacement.frame(in: screen, occupiedOrigins: [])
        XCTAssertTrue(screen.contains(frame))
    }

    /// SPEC §10.3: 復元位置の可視領域クランプ（フェーズ2で使う共通処理）
    func test_画面外の原点は可視領域内にクランプされる() {
        let offscreen = CGPoint(x: 5000, y: -3000)
        let clamped = WindowPlacement.clamp(offscreen, size: size, in: screen)
        XCTAssertEqual(clamped.x, screen.maxX - size.width, accuracy: 0.5)
        XCTAssertEqual(clamped.y, screen.minY, accuracy: 0.5)
    }

    func test_可視領域よりウィンドウが大きい場合は原点に寄せる() {
        let tiny = CGRect(x: 100, y: 100, width: 200, height: 100)
        let clamped = WindowPlacement.clamp(CGPoint(x: 0, y: 0), size: size, in: tiny)
        XCTAssertEqual(clamped, CGPoint(x: 100, y: 100))
    }
}
