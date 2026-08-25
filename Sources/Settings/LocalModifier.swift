/// SPEC §7.3: ローカル（ウィンドウ単位）文字サイズ操作の修飾キー。
/// グローバル操作は ⌘ 固定。スクロールとキーボードショートカットの両方に適用される。
enum LocalModifier: String, CaseIterable {
    case control
    case option

    var displayName: String {
        switch self {
        case .control: return "Control (⌃)"
        case .option: return "Option (⌥)"
        }
    }
}
