import XCTest

/// SPEC §7 の文字サイズモデルとショートカット判定のテスト。
final class FontSizeModelTests: XCTestCase {
    // MARK: - 計算モデル（SPEC §7.1）

    func test_実効サイズはグローバル値とオフセットの和() {
        XCTAssertEqual(FontSizeModel.effectiveSize(global: 14, offset: 3), 17)
        XCTAssertEqual(FontSizeModel.effectiveSize(global: 14, offset: -4), 10)
    }

    func test_実効サイズは9から48にクランプされる() {
        XCTAssertEqual(FontSizeModel.effectiveSize(global: 14, offset: -100), 9)
        XCTAssertEqual(FontSizeModel.effectiveSize(global: 14, offset: 100), 48)
    }

    /// クランプは表示時のみ。オフセット値自体は保持されるので相対関係が復活する。
    func test_上限に張り付いてもオフセットは保持される() {
        var offset: CGFloat = 0
        for _ in 0..<100 {
            offset = FontSizeModel.bumpOffset(offset, direction: 1)
        }
        XCTAssertEqual(offset, 100, "オフセットはクランプされない")
        XCTAssertEqual(FontSizeModel.effectiveSize(global: 14, offset: offset), 48)
        // グローバル値を下げても、まだ上限に張り付いたまま（相対関係は失われていない）
        XCTAssertEqual(FontSizeModel.effectiveSize(global: 9, offset: offset), 48)
        // 十分に大きいオフセットを戻せば元の相対関係に戻る
        XCTAssertEqual(FontSizeModel.effectiveSize(global: 14, offset: 3), 17)
    }

    func test_グローバル値自体はクランプして保持する() {
        XCTAssertEqual(FontSizeModel.clampGlobal(100), 48)
        XCTAssertEqual(FontSizeModel.clampGlobal(0), 9)
        XCTAssertEqual(FontSizeModel.clampGlobal(20), 20)
        XCTAssertEqual(FontSizeModel.clampGlobal(.nan), FontSizeModel.defaultGlobalSize)
    }

    func test_ステップは1pt() {
        XCTAssertEqual(FontSizeModel.bumpGlobal(14, direction: 1), 15)
        XCTAssertEqual(FontSizeModel.bumpGlobal(14, direction: -1), 13)
        XCTAssertEqual(FontSizeModel.bumpGlobal(48, direction: 1), 48, "上限で止まる")
        XCTAssertEqual(FontSizeModel.bumpGlobal(9, direction: -1), 9, "下限で止まる")
    }

    func test_グローバル値を変えても各ウィンドウの相対関係は保たれる() {
        let offsets: [CGFloat] = [-3, 0, 6]
        let before = offsets.map { FontSizeModel.effectiveSize(global: 14, offset: $0) }
        let after = offsets.map { FontSizeModel.effectiveSize(global: 18, offset: $0) }
        XCTAssertEqual(before, [11, 14, 20])
        XCTAssertEqual(after, [15, 18, 24])
    }

    // MARK: - キーバインド（SPEC §7.2）

    private func command(_ key: String, _ modifiers: ModifierState,
                         _ localModifier: LocalModifier = .control) -> FontSizeCommand? {
        FontSizeShortcut.command(characters: key, modifiers: modifiers, localModifier: localModifier)
    }

    func test_コマンドキーはグローバル操作() {
        XCTAssertEqual(command(";", ModifierState(command: true)), .increaseGlobal)
        XCTAssertEqual(command("=", ModifierState(command: true)), .increaseGlobal)
        // JIS 配列では + が ; の Shift 側
        XCTAssertEqual(command(";", ModifierState(command: true, shift: true)), .increaseGlobal)
        XCTAssertEqual(command("+", ModifierState(command: true, shift: true)), .increaseGlobal)
        XCTAssertEqual(command("-", ModifierState(command: true)), .decreaseGlobal)
        XCTAssertEqual(command("0", ModifierState(command: true)), .resetGlobal)
    }

    func test_既定のローカル修飾キーはControl() {
        XCTAssertEqual(command(";", ModifierState(control: true)), .increaseLocal)
        XCTAssertEqual(command("-", ModifierState(control: true)), .decreaseLocal)
        XCTAssertEqual(command("0", ModifierState(control: true)), .resetLocal)
    }

    func test_設定でOptionに変えるとOption側がローカルになる() {
        XCTAssertEqual(command(";", ModifierState(option: true), .option), .increaseLocal)
        XCTAssertNil(command(";", ModifierState(control: true), .option), "Control は効かなくなる")
        XCTAssertNil(command(";", ModifierState(option: true), .control), "Option は効かなくなる")
    }

    func test_修飾キーなしや無関係なキーは対象外() {
        XCTAssertNil(command(";", ModifierState()))
        XCTAssertNil(command("a", ModifierState(command: true)))
        XCTAssertNil(command("1", ModifierState(command: true)))
    }

    func test_コマンドと他の修飾キーの組み合わせは対象外() {
        // ⌘⌃; のような組み合わせで誤動作しない
        XCTAssertNil(command(";", ModifierState(command: true, control: true)))
        XCTAssertNil(command(";", ModifierState(command: true, option: true)))
    }

    // MARK: - スクロール（SPEC §7.2）

    func test_スクロールのスコープ判定() {
        XCTAssertEqual(FontSizeShortcut.scrollScope(modifiers: ModifierState(command: true),
                                                    localModifier: .control), true)
        XCTAssertEqual(FontSizeShortcut.scrollScope(modifiers: ModifierState(control: true),
                                                    localModifier: .control), false)
        XCTAssertEqual(FontSizeShortcut.scrollScope(modifiers: ModifierState(option: true),
                                                    localModifier: .option), false)
        XCTAssertNil(FontSizeShortcut.scrollScope(modifiers: ModifierState(),
                                                  localModifier: .control))
        XCTAssertNil(FontSizeShortcut.scrollScope(modifiers: ModifierState(shift: true),
                                                  localModifier: .control))
    }
}
