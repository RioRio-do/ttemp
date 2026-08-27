import XCTest

/// SPEC §9 / §12.1: 実行時言語切替と、言語に依存する表示名を検証する。
final class LocalizationTests: XCTestCase {
    private let suite = "Ttemp.LocalizationTests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        L10n.defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        L10n.defaults.removePersistentDomain(forName: suite)
        L10n.defaults = .standard
        super.tearDown()
    }

    func test_言語名は表示中の言語に左右されない() {
        XCTAssertEqual(AppLanguage.japanese.displayName, "日本語")
        XCTAssertEqual(AppLanguage.english.displayName, "English")
    }

    func test_日本語と英語を実行時に切り替えられる() {
        L10n.current = .japanese
        XCTAssertEqual(L10n.pick("日本語", "English"), "日本語")

        L10n.current = .english
        XCTAssertEqual(L10n.pick("日本語", "English"), "English")
    }

    func test_言語変更は値が変わるときだけ通知する() {
        L10n.current = .japanese
        var count = 0
        let observer = NotificationCenter.default.addObserver(
            forName: L10n.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        L10n.current = .japanese
        L10n.current = .english

        XCTAssertEqual(count, 1)
    }

    func test_固定モードの表示名は短い日英表記() {
        L10n.current = .japanese
        XCTAssertEqual(NewWindowPinMode.allCases.map(\.displayName),
                       ["なし", "空なら閉じる", "空でも固定"])

        L10n.current = .english
        XCTAssertEqual(NewWindowPinMode.allCases.map(\.displayName),
                       ["Off", "Close if empty", "Keep if empty"])
    }

    func test_画像の元形式表示は短い日英表記() {
        L10n.current = .japanese
        XCTAssertEqual(ImageExportFormat.original(fileExtension: "gif").displayName,
                       "元の形式 (GIF)")

        L10n.current = .english
        XCTAssertEqual(ImageExportFormat.original(fileExtension: "gif").displayName,
                       "Original (GIF)")
    }
}
