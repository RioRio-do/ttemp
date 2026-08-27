import AppKit
import XCTest

final class StatusItemInteractionCheckTests: XCTestCase {
    func testRequiresBothMouseUpActionsInEitherOrder() {
        for actions: [NSEvent.EventType] in [[.leftMouseUp, .rightMouseUp], [.rightMouseUp, .leftMouseUp]] {
            var check = StatusItemInteractionCheck()
            XCTAssertFalse(check.record(actions[0]))
            XCTAssertFalse(check.record(actions[0]))
            XCTAssertTrue(check.record(actions[1]))
            XCTAssertFalse(check.record(actions[1]))
            XCTAssertFalse(check.record(actions[0]))
        }
    }

    func testProgrammaticKeyboardAndOtherMouseEventsDoNotCount() {
        var check = StatusItemInteractionCheck()
        for type: NSEvent.EventType? in [nil, .keyUp, .keyDown, .leftMouseDown, .rightMouseDown,
                                       .otherMouseUp, .mouseMoved, .scrollWheel, .flagsChanged] {
            XCTAssertFalse(check.record(type))
        }
        XCTAssertFalse(check.record(.leftMouseUp))
        XCTAssertTrue(check.record(.rightMouseUp))
    }

    func testIndependentChecksDoNotShareProgress() {
        var first = StatusItemInteractionCheck()
        var second = StatusItemInteractionCheck()
        XCTAssertFalse(first.record(.leftMouseUp))
        XCTAssertFalse(second.record(.rightMouseUp))
    }
}
