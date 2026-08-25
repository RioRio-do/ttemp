import AppKit

/// 言語に依存しない最小構成の「Ttemp について」。
///
/// 標準 About panel はアプリ内の言語選択ではなく macOS の表示言語を使うため、
/// Ttemp / version / GitHub だけの独自 panel にして言語混在を避ける。
final class AboutPanel: NSObject, NSWindowDelegate {
    private static let shared = AboutPanel()

    private var window: NSWindow?

    static func show() {
        shared.showWindow()
    }

    private func showWindow() {
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 210),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Ttemp"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Ttemp")
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let name = NSTextField(labelWithString: "Ttemp")
        name.font = .systemFont(ofSize: 20, weight: .semibold)
        name.alignment = .center

        let version = NSTextField(labelWithString: AppInfo.displayVersion)
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .secondaryLabelColor
        version.alignment = .center
        version.setAccessibilityLabel(AppInfo.displayVersion)

        let github = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        github.isBordered = false
        github.contentTintColor = .linkColor
        github.setAccessibilityLabel("GitHub")

        let stack = NSStackView(views: [icon, name, version, github])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: 4),
        ])
        window.contentView = content
        return window
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(AppInfo.repositoryURL)
    }
}
