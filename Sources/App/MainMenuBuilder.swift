import AppKit

/// `NSApp.mainMenu` の組み立て（PLAN §3.1）。
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
        let about = appMenu.addItem(withTitle: "Ttemp について",
                                    action: #selector(AppDelegate.showAboutPanel(_:)),
                                    keyEquivalent: "")
        about.target = NSApp.delegate
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 編集メニュー
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        // SPEC §5.1: ⌘F で検索、⌘⌥F で置換
        let find = editMenu.addItem(withTitle: "検索…",
                                    action: #selector(NSTextView.performTextFinderAction(_:)),
                                    keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        let replace = editMenu.addItem(withTitle: "置換…",
                                       action: #selector(NSTextView.performTextFinderAction(_:)),
                                       keyEquivalent: "f")
        replace.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        replace.keyEquivalentModifierMask = [.command, .option]
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // ウィンドウメニュー（⌘W で閉じる。SPEC §3.5）
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "ウィンドウ")
        windowMenu.addItem(withTitle: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
