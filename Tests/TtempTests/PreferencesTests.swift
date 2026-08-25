import XCTest

/// SPEC §7.3 / §9: UserDefaults の既定値と旧設定からの移行を検証する。
final class PreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.am921.ttemp.tests.preferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_未設定時の既定値() {
        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.globalFontSize, FontSizeModel.defaultGlobalSize)
        XCTAssertEqual(preferences.localModifier, .control)
        XCTAssertEqual(preferences.newWindowPinMode, .pinnedDismissEmpty)
        XCTAssertFalse(preferences.hasCompletedOnboarding)
        XCTAssertFalse(preferences.suppressPermissionAlert)
    }

    func test_旧修飾キー設定を個別操作キーへ引き継ぐ() {
        defaults.set(LocalModifier.option.rawValue, forKey: "globalModifier")

        XCTAssertEqual(Preferences(defaults: defaults).localModifier, .option)
    }

    func test_新しい修飾キー設定を旧設定より優先する() {
        defaults.set(LocalModifier.option.rawValue, forKey: "globalModifier")
        defaults.set(LocalModifier.control.rawValue, forKey: "localModifier")

        XCTAssertEqual(Preferences(defaults: defaults).localModifier, .control)
    }

    func test_旧固定設定trueは空でも固定へ移行する() {
        defaults.set(true, forKey: "pinsNewWindowsByDefault")

        XCTAssertEqual(Preferences(defaults: defaults).newWindowPinMode, .pinnedKeepEmpty)
    }

    func test_旧固定設定falseは固定なしへ移行する() {
        defaults.set(false, forKey: "pinsNewWindowsByDefault")

        XCTAssertEqual(Preferences(defaults: defaults).newWindowPinMode, .unpinned)
    }

    func test_新しい固定設定を旧設定より優先する() {
        defaults.set(true, forKey: "pinsNewWindowsByDefault")
        defaults.set(NewWindowPinMode.unpinned.rawValue, forKey: "newWindowPinMode")

        XCTAssertEqual(Preferences(defaults: defaults).newWindowPinMode, .unpinned)
    }
}

