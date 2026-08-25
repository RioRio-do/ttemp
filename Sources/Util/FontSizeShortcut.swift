/// キー入力から文字サイズ操作を決める（SPEC §7.2）。
/// ⌘ がグローバル、設定の修飾キー（既定 Control）がローカル。
/// `NSEvent` に依存させず純粋な判定にしてテストする。
enum FontSizeCommand: Equatable {
    case increaseLocal
    case decreaseLocal
    case resetLocal
    case increaseGlobal
    case decreaseGlobal
    case resetGlobal

    var isGlobal: Bool {
        switch self {
        case .increaseGlobal, .decreaseGlobal, .resetGlobal: return true
        default: return false
        }
    }
}

struct ModifierState: Equatable {
    var command = false
    var control = false
    var option = false
    var shift = false

    init(command: Bool = false, control: Bool = false, option: Bool = false, shift: Bool = false) {
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
    }

    func matches(_ modifier: LocalModifier) -> Bool {
        switch modifier {
        case .control: return control && !command && !option
        case .option: return option && !command && !control
        }
    }

    var isCommandOnly: Bool { command && !control && !option }
}

enum FontSizeShortcut {
    /// SPEC §7.2: 拡大は `;` `⇧;`(＝`+`) `=` のすべてを受け付ける（JIS 配列では `+` が `;` の Shift 側）。
    private static let increaseKeys: Set<String> = [";", "+", "=", ":"]
    private static let decreaseKeys: Set<String> = ["-", "_"]
    private static let resetKeys: Set<String> = ["0"]

    /// - Parameter characters: `charactersIgnoringModifiers`
    static func command(characters: String,
                        modifiers: ModifierState,
                        localModifier: LocalModifier) -> FontSizeCommand? {
        let key = characters.lowercased()

        if modifiers.isCommandOnly {
            if increaseKeys.contains(key) { return .increaseGlobal }
            if decreaseKeys.contains(key) { return .decreaseGlobal }
            if resetKeys.contains(key) { return .resetGlobal }
            return nil
        }

        if modifiers.matches(localModifier) {
            if increaseKeys.contains(key) { return .increaseLocal }
            if decreaseKeys.contains(key) { return .decreaseLocal }
            if resetKeys.contains(key) { return .resetLocal }
        }
        return nil
    }

    /// スクロールによる拡大縮小（SPEC §7.2）。
    /// - Returns: グローバル操作なら true、ローカル操作なら false、対象外なら nil
    static func scrollScope(modifiers: ModifierState, localModifier: LocalModifier) -> Bool? {
        if modifiers.isCommandOnly { return true }
        if modifiers.matches(localModifier) { return false }
        return nil
    }
}
