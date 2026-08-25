import AppKit
import CoreGraphics

/// `CGEventTap` のライフサイクル管理（SPEC §2.2 / §11.1）。
///
/// listen-only タップでキーとマウスの押下を監視し、`ShiftChordDetector` に流す。
final class EventTapController {
    /// 左右 Shift の同時押しが成立したときに呼ばれる（メインスレッド）
    var onChordFired: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// タップに渡した自分自身への参照。タップが生きている間は必ず自分も生かす
    /// （`passUnretained` だと、所有者が先に解放された瞬間にコールバックが
    /// ダングリングポインタを掴む）。`stop()` で解放して循環を切る。
    private var tapUserInfo: Unmanaged<EventTapController>?
    private let detector = ShiftChordDetector()

    // SPEC §2.2: 左右 Shift はデバイス依存ビットで判別する
    private static let leftShiftBit: UInt64 = 0x0000_0002
    private static let rightShiftBit: UInt64 = 0x0000_0004
    private static let leftShiftKeyCode: Int64 = 56
    private static let rightShiftKeyCode: Int64 = 60

    func start() {
        guard tap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
            controller.handle(type: type, event: event)
            // listen-only なのでイベントはそのまま通す
            return Unmanaged.passUnretained(event)
        }

        let userInfo = Unmanaged.passRetained(self)
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo.toOpaque()
        ) else {
            userInfo.release()
            NSLog("[Ttemp] CGEvent.tapCreate に失敗した（入力監視権限が未付与の可能性）")
            return
        }
        tapUserInfo = userInfo

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        tap = newTap
        runLoopSource = source
        detector.reset()
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
        // タップを畳んだあとに解放する（コールバックがもう来ないことが確定してから）
        tapUserInfo?.release()
        tapUserInfo = nil
        detector.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // SPEC §2.2: システムに無効化されたら再有効化する。
            // これを忘れると「ある日突然ホットキーが効かなくなる」
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            detector.reset()

        case .keyDown:
            feed(.keyPressed)

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == Self.leftShiftKeyCode || keyCode == Self.rightShiftKeyCode {
                let raw = event.flags.rawValue
                feed(.shiftStateChanged(
                    left: raw & Self.leftShiftBit != 0,
                    right: raw & Self.rightShiftBit != 0
                ))
            } else {
                // SPEC §2 条件3: ⌘ ⌥ ⌃ CapsLock Fn は「打鍵」で判定する。
                // CapsLock のロック状態（flags に立ち続ける）を条件にしてはいけない。
                feed(.otherModifierPressed)
            }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            feed(.mousePressed)

        default:
            break
        }
    }

    private func feed(_ input: ShiftChordInput) {
        guard detector.handle(input) else { return }
        // イベントタップのコールバック内で重い処理をするとタップが無効化されるため、
        // ウィンドウ生成は次のループに回す。
        DispatchQueue.main.async { [weak self] in
            self?.onChordFired?()
        }
    }
}
