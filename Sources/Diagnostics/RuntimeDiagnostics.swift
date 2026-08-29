import AppKit
import Sparkle

/// Opt-in diagnostics for the *packaged executable*, not an unsigned test host.
/// App data is isolated; OS menu-bar registration still uses the app's bundle ID.
/// No TCC, login registration or updater starts.
final class RuntimeDiagnostics {
    let preferences: Preferences
    let stateStore: StateStore
    let clipboard = NSPasteboard.withUniqueName()
    private let directory: URL
    private let defaults: UserDefaults
    private let suite: String
    private let interactive: Bool
    private let probeLibrary: String?
    private var checkCount = 0
    private var statusItemInteractions = StatusItemInteractionCheck()

    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func fromArguments() throws -> RuntimeDiagnostics? {
        let args = CommandLine.arguments
        let automated = args.contains("--self-test")
        let interactive = args.contains("--isolated")
        let disposableCI = args.contains("--disposable-ci")
        guard automated || interactive else {
            if DiagnosticLaunchPolicy.isTestIdentifier(Bundle.main.bundleIdentifier),
               Bundle.main.bundleIdentifier != DiagnosticLaunchPolicy.developmentIdentifier {
                throw Failure(description: "Test apps require --self-test or --isolated")
            }
            guard !disposableCI && !args.contains("--probe-library") else {
                throw Failure(description: "Diagnostic options require --self-test")
            }
            return nil
        }
        guard automated != interactive else { throw Failure(description: "Choose one diagnostic mode") }
        guard DiagnosticLaunchPolicy.allows(identifier: Bundle.main.bundleIdentifier,
                                            interactive: interactive, disposableCI: disposableCI,
                                            environment: ProcessInfo.processInfo.environment) else {
            throw Failure(description: "Diagnostics require a development/test bundle ID; use scripts/test-release.sh. Production diagnostics are restricted to disposable CI.")
        }
        var probe: String?
        if let index = args.firstIndex(of: "--probe-library") {
            guard automated, args.indices.contains(index + 1), args[index + 1].hasPrefix("/") else {
                throw Failure(description: "--probe-library requires --self-test and an absolute path")
            }
            probe = args[index + 1]
        }
        return try RuntimeDiagnostics(interactive: interactive, probeLibrary: probe)
    }

    private init(interactive: Bool, probeLibrary: String?) throws {
        self.interactive = interactive
        self.probeLibrary = probeLibrary
        suite = "com.am921.ttemp.diagnostics.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw Failure(description: "Cannot create isolated defaults")
        }
        self.defaults = defaults
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        preferences = Preferences(defaults: defaults, allowsSystemIntegration: false)
        stateStore = StateStore(directory: directory)
        L10n.defaults = defaults
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        clipboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    func start(windowManager: WindowManager, statusItem: StatusItemController, updater: SPUUpdater) {
        if interactive {
            statusItem.onMouseInteraction = { [weak self] type in
                guard let self, self.statusItemInteractions.record(type) else { return }
                print("TTEMP_STATUS_ITEM_INTERACTION_OK")
                fflush(stdout)
            }
            statusItem.setPermissionWarning(true)
            preferences.newWindowPinMode = .pinnedKeepEmpty
            windowManager.createNoteActivating()
            print("TTEMP_ISOLATED_READY")
            fflush(stdout)
            return
        }
        Task { @MainActor in
            do {
                try await run(windowManager, statusItem: statusItem, updater: updater)
                print("TTEMP_SELF_TEST_OK \(checkCount) checks")
                fflush(stdout)
                NSApp.terminate(nil)
            } catch {
                fputs("TTEMP_SELF_TEST_FAILED: \(error)\n", stderr)
                windowManager.closeAllWithoutCopying()
                cleanup()
                exit(1)
            }
        }
    }

    private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checkCount += 1
    }

    @MainActor private func waitFor(_ description: String, _ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure(description: description) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        checkCount += 1
    }

    private func textView(in view: NSView?) -> NoteTextView? {
        if let text = view as? NoteTextView { return text }
        return view?.subviews.lazy.compactMap { self.textView(in: $0) }.first
    }

    private func newNote(_ manager: WindowManager, statusItem: StatusItemController) throws -> NoteWindowController {
        let count = manager.controllers.count
        let menu = statusItem.makeMenu()
        guard let item = menu.items.first, let action = item.action else {
            throw Failure(description: "Missing New Note action")
        }
        try check(NSApp.sendAction(action, to: item.target, from: item), "Menu action did not dispatch")
        try check(manager.controllers.count == count + 1, "Menu did not create a note")
        guard let controller = manager.controllers.last else { throw Failure(description: "Missing note") }
        return controller
    }

    @MainActor private func run(_ manager: WindowManager, statusItem: StatusItemController,
                                updater: SPUUpdater) async throws {
        try check(NSApp.activationPolicy() == .accessory, "Dockless activation policy")
        try check(NSApp.mainMenu != nil, "Missing responder-chain menu")
        try check(statusItem.isConfigured, "Invalid status item configuration")
        // NSStatusItem.isVisible expresses requested visibility, not actual screen presence.
        // Do not turn a successful runtime test into an assertion about OS presentation.
        print("TTEMP_STATUS_ITEM_VISIBILITY_UNVERIFIED")
        try check(!updater.canCheckForUpdates, "Diagnostics must not start network updates")
        if let probeLibrary {
            let handle = dlopen(probeLibrary, RTLD_NOW | RTLD_LOCAL)
            if let handle { dlclose(handle) }
            try check(handle == nil, "Library constraint allowed unexpected third-party code")
            let error = dlerror().map { String(cString: $0) } ?? ""
            // dyld on some macOS versions spells the last word "contraint".
            try check(error.contains("Library violates process"), "Library probe failed for an unrelated reason: \(error)")
        }
        for language in AppLanguage.allCases {
            L10n.current = language
            let title = language == .japanese ? "新規メモ" : "New Note"
            try check(statusItem.makeMenu().items.first?.title == title, "Menu language did not switch")
            statusItem.setPermissionWarning(true)
            try check(statusItem.isConfigured, "Invalid permission-warning icon configuration")
            try check(statusItem.makeMenu().items.count > 7, "Missing permission menu action")
        }
        statusItem.setPermissionWarning(false)
        L10n.current = .english
        preferences.newWindowPinMode = .pinnedKeepEmpty
        let note = try newNote(manager, statusItem: statusItem)
        try check(note.window.isVisible, "Note window is not visible")
        guard let editor = textView(in: note.window.contentView) else { throw Failure(description: "Missing editor") }
        guard let undo = editor.undoManager else { throw Failure(description: "Missing undo manager") }
        let pasted = "日本語 📝\nsecond\u{00a0}line"
        do {
            // Direct calls in a Task are not separate AppKit input events. Model
            // their undo boundaries explicitly instead of racing run-loop timing.
            let groupsByEvent = undo.groupsByEvent
            undo.groupsByEvent = false
            defer { undo.groupsByEvent = groupsByEvent }
            func edit(_ action: () -> Void) {
                undo.beginUndoGrouping()
                action()
                editor.breakUndoCoalescing()
                undo.endUndoGrouping()
            }
            edit { editor.insertText("日本語 📝", replacementRange: NSRange(location: 0, length: 0)) }
            try check(note.text == "日本語 📝", "Unicode text input")
            clipboard.clearContents()
            clipboard.setString("\r\nsecond\u{00a0}line", forType: .string)
            edit { editor.paste(nil) }
            try check(note.text == pasted, "Plain-text paste normalization")
            undo.undo()
            try check(note.text == "日本語 📝", "Paste undo")
            undo.redo()
            try check(note.text == pasted, "Paste redo")
            editor.setSelectedRange(NSRange(location: 0, length: (note.text as NSString).length))
            editor.copy(nil)
            try check(clipboard.string(forType: .string) == pasted, "Copy must use the isolated clipboard")
            edit { editor.cut(nil) }
            try check(note.text.isEmpty, "Cut must remove selected text")
            undo.undo()
            try check(note.text == pasted, "Cut undo")
        }
        editor.setSelectedRange(NSRange(location: 0, length: (note.text as NSString).length))
        editor.insertText(String(repeating: "x", count: PlainTextSanitizer.maximumUTF16Length + 1),
                          replacementRange: editor.selectedRange())
        try check(note.text == pasted, "Oversized typing must not replace content")
        note.fontSizeOffset = 3
        manager.globalFontSize = 22
        try check(editor.font?.pointSize == 25, "Global/local font size propagation")
        note.window.setContentSize(NSSize(width: 420, height: 290))
        try check(note.isPinned && note.window.level == .floating, "Pinned window level")

        let imageNote = try newNote(manager, statusItem: statusItem)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else {
            throw Failure(description: "Cannot make image fixture")
        }
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.red, atX: x, y: y) } }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure(description: "Cannot encode image fixture")
        }
        clipboard.clearContents()
        clipboard.setData(png, forType: .png)
        try check(imageNote.handlePasteboard(clipboard, isDrop: true), "Image drop rejected")
        try await waitFor("Image import timed out") { imageNote.mode == .image }
        try check(imageNote.menuThumbnail != nil, "Missing image menu thumbnail")
        clipboard.clearContents()
        clipboard.setString("must not replace image", forType: .string)
        try check(!imageNote.handlePasteboard(clipboard, isDrop: false), "Image must reject text")
        try check(imageNote.mode == .image, "Rejected paste changed image")
        guard let imageSnapshot = imageNote.snapshot else { throw Failure(description: "Missing image snapshot") }
        try checkTextResizing(imageSnapshot: imageSnapshot)

        // Persist real windows, destroy them without copying, then restore from disk.
        let expected = manager.snapshot()
        try check(expected.notes.count == 2, "Missing snapshots")
        stateStore.flush()
        let diskStore = StateStore(directory: directory)
        guard case .loaded(let saved) = diskStore.load() else { throw Failure(description: "State reload failed") }
        try check(saved == expected, "Persisted state differs")
        let clipboardCount = clipboard.changeCount
        manager.closeAllWithoutCopying()
        try check(clipboard.changeCount == clipboardCount, "Quit modified clipboard")
        manager.restore(saved)
        try check(manager.controllers.count == 2, "Window restore count")
        try check(manager.snapshot() == saved, "Restored content, pin, font or geometry differs")

        guard let restoredImage = manager.controllers.first(where: { $0.mode == .image }),
              let restoredText = manager.controllers.first(where: { $0.mode == .filledText }) else {
            throw Failure(description: "Restored modes differ")
        }
        guard case .image(let reference) = restoredImage.content else {
            throw Failure(description: "Missing image reference")
        }
        let originals = ImageStore(directory: stateStore.imagesDirectoryURL)
        let exportingOriginal = try originals.openOriginal(reference)
        defer { try? exportingOriginal.close() }
        restoredImage.requestClose()
        try await waitFor("Image close did not finish") { manager.controllers.count == 1 }
        try check(clipboard.data(forType: .png) == png, "Close did not preserve original PNG")
        stateStore.flush()
        try check(originals.load(reference) == nil, "Closed image was not collected")
        let exported = try ImageStore.readOriginal(from: exportingOriginal)
        try check(exported == png, "Closing during export lost the original")
        restoredText.requestClose()
        try await waitFor("Text close did not finish") { manager.controllers.isEmpty }
        try check(clipboard.string(forType: .string) == pasted, "Close did not copy full text")
        stateStore.flush()
        guard case .loaded(let empty) = diskStore.load() else { throw Failure(description: "Empty reload failed") }
        try check(empty.notes.isEmpty, "Closed notes were persisted")
        try check(statusItem.isConfigured, "Status item configuration lost after last window closed")
    }

    private func checkTextResizing(imageSnapshot: NoteSnapshot) throws {
        let note = NoteWindowController(frame: NSRect(x: 100, y: 100, width: 480, height: 320),
                                        imageStore: ImageStore(directory: stateStore.imagesDirectoryURL),
                                        preferences: preferences, clipboard: clipboard)
        note.isPinned = true
        note.present(activating: false)
        defer { note.closeWithoutCopying() }
        guard let editor = textView(in: note.window.contentView),
              let scrollView = editor.enclosingScrollView else {
            throw Failure(description: "Missing text scroll view")
        }
        try check(scrollView.layerContentsRedrawPolicy == .duringViewResize,
                  "Text scroll view must redraw while resizing")
        try check(scrollView.contentView.layerContentsRedrawPolicy == .duringViewResize,
                  "Text clip view must redraw while resizing")

        // Grow/shrink through the point where the whole document fits, with the
        // caret at the end as in normal typing. The title bar must never cover it.
        editor.string = String(repeating: "あいうえお Resize test\n", count: 12)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.scroll(.zero)
        for size in [NSSize(width: 480, height: 200), NSSize(width: 480, height: 600),
                     NSSize(width: 300, height: 250), NSSize(width: 520, height: 600),
                     NSSize(width: 480, height: 200)] {
            note.window.setContentSize(size)
            note.window.contentView?.layoutSubtreeIfNeeded()
            note.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification,
                                                     object: note.window))
            try checkTextViewport(note, editor: editor, context: "Resize to \(size)")
            try check(abs(scrollView.contentView.bounds.minY) < 0.5,
                      "Resizing shifted the top of the document")
        }

        let find = NSMenuItem()
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        editor.performTextFinderAction(find)
        note.window.contentView?.layoutSubtreeIfNeeded()
        try check(scrollView.isFindBarVisible, "Find bar did not open")
        try checkTextViewport(note, editor: editor, context: "Find bar")
        scrollView.isFindBarVisible = false
        editor.string = "Short note"
        note.window.setContentSize(NSSize(width: 480, height: 600))
        note.window.contentView?.layoutSubtreeIfNeeded()
        note.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification,
                                                 object: note.window))
        try checkTextViewport(note, editor: editor, context: "Short note")
        try check(abs(editor.frame.height - scrollView.contentView.bounds.height) < 0.5,
                  "Short text does not fill the resized viewport")

        // Reattaching the editor after image mode must restore the same layout,
        // even if the window changed size while the editor was detached.
        for height: CGFloat in [250, 550] {
            editor.string = ""
            try check(note.restore(from: imageSnapshot), "Could not install image resize fixture")
            note.window.setContentSize(NSSize(width: 480, height: height))
            note.removeImage()
            note.window.contentView?.layoutSubtreeIfNeeded()
            try checkTextViewport(note, editor: editor, context: "Image removal at height \(height)")
            try check(abs(editor.frame.height - scrollView.contentView.bounds.height) < 0.5,
                      "Image removal left an incorrectly sized text viewport")
        }
    }

    private func checkTextViewport(_ note: NoteWindowController, editor: NoteTextView, context: String) throws {
        guard let clipView = editor.enclosingScrollView?.contentView else {
            throw Failure(description: "Missing text clip view")
        }
        let viewport = clipView.convert(clipView.bounds, to: nil)
        try check(note.window.contentLayoutRect.insetBy(dx: -0.5, dy: -0.5).contains(viewport),
                  "\(context): text viewport overlaps the title bar after resizing")
        try check(editor.frame.height + 0.5 >= clipView.bounds.height,
                  "\(context): text height \(editor.frame.height), minimum \(editor.minSize.height), viewport \(clipView.bounds.height)")
    }
}
