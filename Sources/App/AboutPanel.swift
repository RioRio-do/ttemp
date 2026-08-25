import AppKit

/// 「Ttemp について」。標準の About パネルにバージョンと GitHub へのリンクを出す。
enum AboutPanel {
    static func show() {
        // LSUIElement のアプリは非アクティブのままだとパネルが背面に出る
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: AppInfo.repositoryURL.absoluteString,
            attributes: [
                .link: AppInfo.repositoryURL,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
