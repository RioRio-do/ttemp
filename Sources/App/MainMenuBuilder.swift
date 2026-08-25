import AppKit

/// `NSApp.mainMenu` の組み立て（SPEC §8.4）。
///
/// `LSUIElement` のアプリはメニューバーに自前のメニューを表示しないが、
/// mainMenu を設定しておかないと `⌘V` や `⌘Z` すら `performKeyEquivalent` を通らず、
/// `NSTextView` の基本的な編集ショートカットが一切効かなくなる。
enum MainMenuBuilder {
    static func install() {
        let mainMenu = NSMenu()

        // アプリメニュー（SPEC §1: ⌘Q は割り当てない）
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = appMenu.addItem(withTitle: L10n.pick("Ttemp について", "About Ttemp"),
                                    action: #selector(AppDelegate.showAboutPanel(_:)),
                                    keyEquivalent: "")
        about.target = NSApp.delegate
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 編集メニュー
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.pick("編集", "Edit"))
        editMenu.addItem(withTitle: L10n.pick("取り消す", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L10n.pick("やり直す", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.pick("カット", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.pick("コピー", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.pick("ペースト", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.pick("すべてを選択", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        // SPEC §5.1: ⌘F で検索、⌘⌥F で置換
        let find = editMenu.addItem(withTitle: L10n.pick("検索…", "Find…"),
                                    action: #selector(NSTextView.performTextFinderAction(_:)),
                                    keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        let replace = editMenu.addItem(withTitle: L10n.pick("置換…", "Find and Replace…"),
                                       action: #selector(NSTextView.performTextFinderAction(_:)),
                                       keyEquivalent: "f")
        replace.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        replace.keyEquivalentModifierMask = [.command, .option]
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // ウィンドウメニュー（⌘W で閉じる。SPEC §3.5）
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.pick("ウィンドウ", "Window"))
        windowMenu.addItem(withTitle: L10n.pick("閉じる", "Close"),
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
