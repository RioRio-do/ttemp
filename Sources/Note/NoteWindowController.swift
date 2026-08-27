import AppKit
import UniformTypeIdentifiers

extension ModifierState {
    init(_ flags: NSEvent.ModifierFlags) {
        self.init(command: flags.contains(.command),
                  control: flags.contains(.control),
                  option: flags.contains(.option),
                  shift: flags.contains(.shift))
    }
}

/// 1ウィンドウ = 1インスタンス。ウィンドウの生成・閉じる・自動消滅・モード遷移を担う。
final class NoteWindowController: NSObject, NSWindowDelegate, NSTextViewDelegate,
                                  NotePasteHandling, NoteShortcutHandling {
    /// SPEC §3.7: アニメーション時間
    static let fadeDuration: TimeInterval = 0.12

    /// 画像モードの中身。原本のバイト列は常に ImageStore（ディスク）にあり、
    /// コピー／書き出しの時にだけ読み直す（巨大画像を常駐メモリに持たないため）。
    private struct ImagePayload {
        let reference: ImageReference
        let displayImage: NSImage
    }

    let id: UUID
    let window: NoteWindow

    private let textView: NoteTextView
    private let scrollView: NSScrollView
    private var imageView: NoteImageView?
    private var imagePayload: ImagePayload?
    /// 非同期画像取り込みの最新要求。文字入力・削除・後発取り込み・終了で無効化する。
    private var pendingImageImportID: UUID?

    private let imageStore: ImageStore
    private let preferences: Preferences
    private let clipboard: NSPasteboard

    /// SPEC §3.2 / §3.3: 最前面固定
    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            window.level = isPinned ? .floating : .normal
            updatePinIndicator()
            onStateChanged?()
        }
    }

    /// SPEC §7.1: グローバル値からの相対オフセット。クランプせず生の値を保持する。
    var fontSizeOffset: CGFloat = 0 {
        didSet {
            guard fontSizeOffset != oldValue else { return }
            applyFontSize()
            onStateChanged?()
        }
    }

    private var globalFontSize: CGFloat

    /// 閉じ終わったときの通知
    var onClosed: ((NoteWindowController) -> Void)?
    /// SPEC §4: 閉じる操作の開始時、close() より前にフォーカスを次のアプリへ譲る要求。
    /// close() 後の OS 任せのハンドオフに委ねると、無関係なアプリが一瞬前面に出る。
    var onRestoreFocus: (() -> Void)?
    /// 保存対象の状態が変化したときの通知（SPEC §10.1 の逐次保存のトリガー）
    var onStateChanged: (() -> Void)?
    /// SPEC §7.1: グローバル文字サイズの変更要求。`direction` が nil ならリセット
    var onGlobalFontSizeChange: ((_ direction: Int?) -> Void)?

    private var isClosing = false
    private var pinAccessory: NSTitlebarAccessoryViewController?
    private weak var pinButton: NSButton?
    private var scrollAccumulator: CGFloat = 0
    /// `scrollAccumulator` に積まれているのが精密デルタ（トラックパッド）かどうか
    private var scrollAccumulatorIsPrecise = false
    /// 累積中の操作スコープ（true=グローバル、false=ローカル）。途中切替時は持ち越さない。
    private var scrollAccumulatorScope: Bool?

    var text: String { textView.string }

    /// SPEC §3.2: 空の判定。画像モードは常に「空ではない」
    var isEmpty: Bool { content.isEmpty }

    var content: NoteContent {
        if let imagePayload {
            return .image(imagePayload.reference)
        }
        return .text(textView.string)
    }

    /// SPEC §6.1 のモード遷移表の行
    var mode: NoteModeState {
        if imagePayload != nil { return .image }
        return PlainTextSanitizer.isEffectivelyEmpty(textView.string) ? .emptyText : .filledText
    }

    /// SPEC §8.3: メニューバーのウィンドウ一覧に出す表示名（先頭30文字）
    var menuTitle: String {
        if imagePayload != nil { return L10n.pick("画像", "Image") }
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flattened.isEmpty { return L10n.pick("（空のウィンドウ）", "(Empty window)") }
        return flattened.count <= 30 ? flattened : String(flattened.prefix(30)) + "…"
    }

    /// SPEC §8.3: 一覧に出す小さなサムネイル
    var menuThumbnail: NSImage? { imagePayload?.displayImage }

    /// SPEC §10.2: 空ウィンドウは保存対象外
    var snapshot: NoteSnapshot? {
        // フェードアウト中に Quit されても、閉じることを確定したノートを復元しない。
        guard !isClosing, !isEmpty else { return nil }
        return NoteSnapshot(id: id,
                            content: content,
                            frame: FrameSnapshot(window.frame),
                            isPinned: isPinned,
                            fontSizeOffset: Double(fontSizeOffset))
    }

    init(id: UUID = UUID(),
         frame: NSRect,
         globalFontSize: CGFloat = FontSizeModel.defaultGlobalSize,
         imageStore: ImageStore,
         preferences: Preferences = .shared,
         clipboard: NSPasteboard = .general) {
        self.id = id
        self.globalFontSize = globalFontSize
        self.imageStore = imageStore
        self.preferences = preferences
        self.clipboard = clipboard
        window = NoteWindow(contentRect: frame)

        let contentBounds = window.contentView?.bounds ?? NSRect(origin: .zero, size: frame.size)
        scrollView = NSScrollView(frame: contentBounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        // レガシースクロールバー環境（マウス接続時など）でバーの出現により contentSize の
        // 幅が変わると、折り返し位置がその都度ずれる。スクローラ領域を常に確保して、
        // バーが出る前からバーの位置で折り返すようにする（オーバーレイ環境では無影響）。
        scrollView.autohidesScrollers = false
        // 背景はスクロールビュー側でも塗る。透明のままだと clip view が
        // copiesOnScroll でバックストアをブリットしたときに古いピクセルが残り、
        // スクロールで文字が尾を引く（不透明でない clip view で copiesOnScroll を
        // 使ってはいけない、というのが AppKit の前提）。
        // ウィンドウ背景と同色なので見た目は変わらない。
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder

        textView = NoteTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        // SPEC §5.1: 折り返しあり・横スクロールなし
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                       height: .greatestFiniteMagnitude)
        textView.applyPlainTextConfiguration(fontSize: globalFontSize)

        scrollView.documentView = textView
        window.contentView?.addSubview(scrollView)

        super.init()

        window.delegate = self
        window.shortcutHandler = self
        textView.delegate = self
        textView.pasteHandler = self
        textView.clipboard = clipboard
        textView.onEscape = { [weak self] in self?.requestClose() }
        textView.scrollHandler = { [weak self] event in self?.handleScrollWheel(event) ?? false }
        textView.contextMenuProvider = { [weak self] in self?.makeTextContextMenu() }

        // クリップビューの大きさが変わるたびにテキストビューの下限高さを追従させる。
        // ウィンドウのリサイズだけでなく find bar の開閉でも起きるので、
        // windowDidResize ではなくフレーム変化の通知で拾う。
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(clipViewFrameChanged),
                                               name: NSView.frameDidChangeNotification,
                                               object: scrollView.contentView)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(languageDidChange),
                                               name: L10n.didChangeNotification,
                                               object: nil)

        applyFontSize()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - テキストビューの追従

    @objc private func clipViewFrameChanged() {
        updateTextViewMinimumHeight()
    }

    /// テキストビューがクリップビュー全体を覆い続けるようにする。
    ///
    /// `minSize` を生成時の値のままにしておくと、ウィンドウを縦に広げたときに
    /// テキストビューが「テキストの実使用量」までしか伸びず、下部がクリップビューの
    /// 地肌になる。そこはテキストビューではないのでクリックしてもキャレットが立たず、
    /// `isMovableByWindowBackground` によってウィンドウのドラッグになってしまう。
    private func updateTextViewMinimumHeight() {
        let height = scrollView.contentSize.height
        // 再入防止も兼ねる（高さの変更が再びフレーム変化を起こしても2回目は素通り）
        guard textView.minSize.height != height else { return }
        textView.minSize = NSSize(width: 0, height: height)

        guard !window.inLiveResize else {
            // ドラッグ中は「足りなければ広げる」だけにする。`sizeToFit()` はテキストの
            // 使用領域を求めるために全文レイアウトを強制するので、長文のウィンドウを
            // ドラッグリサイズすると毎フレーム走ってカクつく
            // （TextKit 1 に固定しているのも同じ理由。applyPlainTextConfiguration 参照）。
            // 縮めすぎた分は windowDidEndLiveResize で精算する。
            if textView.frame.height < height {
                textView.setFrameSize(NSSize(width: textView.frame.width, height: height))
            }
            return
        }
        textView.sizeToFit()
    }

    // MARK: - ショートカット（SPEC §7.2）

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let characters = event.charactersIgnoringModifiers,
              let command = FontSizeShortcut.command(characters: characters,
                                                     modifiers: ModifierState(event.modifierFlags),
                                                     localModifier: preferences.localModifier) else {
            return false
        }
        return handle(command)
    }

    @discardableResult
    private func handle(_ command: FontSizeCommand) -> Bool {
        // SPEC §7.2: 画像モードのウィンドウでは「そのウィンドウの」文字サイズ操作は無効。
        // グローバル操作は他のテキストウィンドウにも効くのでそのまま通す。
        if !command.isGlobal, !allowsFontSizeChange { return true }

        switch command {
        case .increaseLocal:
            fontSizeOffset = FontSizeModel.bumpOffset(fontSizeOffset, direction: 1)
        case .decreaseLocal:
            fontSizeOffset = FontSizeModel.bumpOffset(fontSizeOffset, direction: -1)
        case .resetLocal:
            // SPEC §7.2: ⌃0（ローカル修飾キー+0）はそのウィンドウのオフセットを0に
            fontSizeOffset = 0
        case .increaseGlobal:
            onGlobalFontSizeChange?(1)
        case .decreaseGlobal:
            onGlobalFontSizeChange?(-1)
        case .resetGlobal:
            // SPEC §7.2: ⌘0 はグローバル値を初期値に。各ウィンドウのオフセットは維持
            onGlobalFontSizeChange?(nil)
        }
        return true
    }

    /// 1ステップ（1pt）に必要なスクロール量。マウスのホイールはライン単位で
    /// 1イベントあたり1前後、トラックパッドの精密デルタはポイント単位で
    /// 1イベントあたり数十来る。同じ閾値を使うとトラックパッドでは一撫でで
    /// 上限／下限まで振り切れるため、デバイスごとに分ける。
    private static let coarseScrollThreshold: CGFloat = 3
    private static let preciseScrollThreshold: CGFloat = 24

    /// SPEC §7.2: ⌘/⌃ + マウススクロール。
    private func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard let isGlobal = FontSizeShortcut.scrollScope(modifiers: ModifierState(event.modifierFlags),
                                                          localModifier: preferences.localModifier) else {
            scrollAccumulator = 0
            scrollAccumulatorScope = nil
            return false
        }

        // 指を離したあとの慣性スクロールで拡大縮小が走り続けないようにする。
        // イベント自体は消費する（テキストのスクロールに落とさない）。
        guard event.momentumPhase.isEmpty else { return true }

        let isPrecise = event.hasPreciseScrollingDeltas
        // ジェスチャの切れ目とデバイスの切り替わりで持ち越しを捨てる
        if event.phase.contains(.began)
            || isPrecise != scrollAccumulatorIsPrecise
            || isGlobal != scrollAccumulatorScope {
            scrollAccumulator = 0
            scrollAccumulatorIsPrecise = isPrecise
            scrollAccumulatorScope = isGlobal
        }

        let threshold = isPrecise ? Self.preciseScrollThreshold : Self.coarseScrollThreshold
        scrollAccumulator += event.scrollingDeltaY
        while abs(scrollAccumulator) >= threshold {
            let direction = scrollAccumulator > 0 ? 1 : -1
            scrollAccumulator -= CGFloat(direction) * threshold
            switch (isGlobal, direction) {
            case (true, 1): handle(.increaseGlobal)
            case (true, _): handle(.decreaseGlobal)
            case (false, 1): handle(.increaseLocal)
            case (false, _): handle(.decreaseLocal)
            }
        }
        return true
    }

    // MARK: - ピン留めの表示（SPEC §3.5）

    /// 透明タイトルバーの右端に小さなピンアイコンを常時表示し、クリックで解除もできる。
    private func updatePinIndicator() {
        if isPinned {
            if pinAccessory == nil {
                let button = NSButton(image: NSImage(),
                                      target: self,
                                      action: #selector(menuTogglePin))
                button.isBordered = false
                button.imageScaling = .scaleProportionallyDown
                button.frame = NSRect(x: 0, y: 0, width: 28, height: 22)

                let container = NSView(frame: button.frame)
                container.addSubview(button)

                let accessory = NSTitlebarAccessoryViewController()
                accessory.view = container
                accessory.layoutAttribute = .right
                window.addTitlebarAccessoryViewController(accessory)
                pinAccessory = accessory
                pinButton = button
            }
            refreshPinIndicatorLocalization()
        } else if let pinAccessory {
            if let index = window.titlebarAccessoryViewControllers.firstIndex(of: pinAccessory) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            self.pinAccessory = nil
            pinButton = nil
        }
    }

    @objc private func languageDidChange() {
        updatePinIndicator()
    }

    private func refreshPinIndicatorLocalization() {
        let accessibility = L10n.pick("固定中", "Pinned")
        pinButton?.image = NSImage(systemSymbolName: "pin.fill",
                                   accessibilityDescription: accessibility)
        pinButton?.toolTip = L10n.pick("固定中（クリックで解除）",
                                      "Pinned (click to unpin)")
        pinButton?.setAccessibilityLabel(accessibility)
    }

    // MARK: - テキストモードの右クリックメニュー（SPEC §8.1）

    private func makeTextContextMenu() -> NSMenu {
        let menu = NSMenu()
        // target は nil のままにしてレスポンダチェーン（＝NSTextView）に解決させる
        menu.addItem(withTitle: L10n.pick("取り消す", "Undo"), action: Selector(("undo:")), keyEquivalent: "")
        menu.addItem(withTitle: L10n.pick("やり直す", "Redo"), action: Selector(("redo:")), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.pick("カット", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L10n.pick("コピー", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L10n.pick("ペースト", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L10n.pick("すべてを選択", "Select All"),
                     action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let find = menu.addItem(withTitle: L10n.pick("検索…", "Find…"),
                                action: #selector(NSTextView.performTextFinderAction(_:)),
                                keyEquivalent: "")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        let replace = menu.addItem(withTitle: L10n.pick("置換…", "Find and Replace…"),
                                   action: #selector(NSTextView.performTextFinderAction(_:)),
                                   keyEquivalent: "")
        replace.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        // SPEC §8.1: 空のテキストモードのときだけ、ファイル選択から画像モードへ入る導線を出す
        if mode == .emptyText {
            menu.addItem(.separator())
            menu.addItem(withTitle: L10n.pick("画像を選択…", "Choose Image…"),
                         action: #selector(menuChooseImage), keyEquivalent: "")
                .target = self
        }
        menu.addItem(.separator())
        let pin = menu.addItem(withTitle: L10n.pick("最前面に固定", "Pin on Top"),
                               action: #selector(menuTogglePin), keyEquivalent: "")
        pin.target = self
        pin.state = isPinned ? .on : .off
        return menu
    }

    /// SPEC §8.1: 「画像を選択…」。選んだファイルはドロップと同じ経路で画像モードにする。
    @objc private func menuChooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            _ = self?.applyImage(from: .imageFile(url))
        }
    }

    // MARK: - 復元

    /// SPEC §10.3: 保存された状態を流し込む。
    ///
    /// - Returns: 復元できたか。false のとき呼び出し側はこのウィンドウを出さず、
    ///   スナップショットをそのまま持ち越すこと。空テキストとして生かしてしまうと
    ///   次の保存で state.json から落ち、孤児掃除で画像の原本まで消える。
    @discardableResult
    func restore(from snapshot: NoteSnapshot) -> Bool {
        switch snapshot.content {
        case .text(let string):
            textView.string = string
        case .image(let reference):
            guard let displayImage = ImageStore.displayImage(at: imageStore.url(for: reference)) else {
                NSLog("[Ttemp] 画像を読めなかったので、このノートは表示せず状態だけ保持する: \(reference.fileName)")
                return false
            }
            // SPEC §10.3: 復元ではウィンドウサイズを保存値のまま使う
            installImage(reference: reference, displayImage: displayImage, resizeWindow: false)
        }
        isPinned = snapshot.isPinned
        fontSizeOffset = CGFloat(snapshot.fontSizeOffset)
        return true
    }

    // MARK: - 文字サイズ（SPEC §7）

    func applyGlobalFontSize(_ size: CGFloat) {
        globalFontSize = size
        applyFontSize()
    }

    /// SPEC §7.2: 画像モードのウィンドウでは文字サイズ操作は無効。
    /// ただしオフセット値自体は保持する（画像を削除すると元のサイズで戻る）。
    var allowsFontSizeChange: Bool { imagePayload == nil }

    private func applyFontSize() {
        let effective = FontSizeModel.effectiveSize(global: globalFontSize, offset: fontSizeOffset)
        textView.applyFontSize(effective)
    }

    // MARK: - 表示

    /// SPEC §3.7: 0.12秒のフェードイン。`activating` が true のときキーウィンドウにする。
    func present(activating: Bool) {
        window.prepareForFadeIn()
        if activating {
            // SPEC §3.1: 他アプリの手前に出し、確実にキーウィンドウにする。
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(imageView ?? textView)
        } else {
            // SPEC §10.3: 復元時は他アプリのフォーカスを奪わない。
            // orderFrontRegardless は非アクティブでも他アプリの手前に割り込むので使わない。
            window.orderFront(nil)
        }
        window.fade(to: 1, duration: Self.fadeDuration)
    }

    func orderFront() {
        window.orderFront(nil)
    }

    // MARK: - ペースト / ドロップ（SPEC §5.4 / §6.1）

    func handlePasteboard(_ pasteboard: NSPasteboard, isDrop: Bool) -> Bool {
        let decision = PasteboardReader.decide(PasteboardReader.snapshot(of: pasteboard))
        switch PasteboardReader.resolve(decision, mode: mode) {
        case .insertText(let string):
            textView.insertSanitized(string)
            return true

        case .setImage(let imageDecision):
            return applyImage(from: imageDecision)

        case .reject:
            window.shake()
            return false

        case .ignore:
            return false
        }
    }

    private func applyImage(from decision: PasteDecision) -> Bool {
        let loadData: () throws -> (data: Data, hintedExtension: String)
        switch decision {
        case .image(let pasteboardData, let ext):
            loadData = { (pasteboardData, ext) }
        case .imageFile(let url):
            // SPEC §6.3: ファイルのバイト列をそのまま読む（NSImage 経由にすると原本が失われる）
            loadData = { (try ImageStore.loadImportData(from: url), url.pathExtension) }
        default:
            return false
        }

        let importID = UUID()
        pendingImageImportID = importID
        let imageStore = self.imageStore
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (data, hintedExtension) = try loadData()
                // 拡張子ではなく実バイトを正とする。偽装／誤った拡張子のファイルでも、
                // 「元形式」保存と永続化ファイル名を実形式に揃える。
                let detectedExtension = try ImageStore.validatedFileExtension(of: data)
                let fileExtension = detectedExtension == "dat" ? hintedExtension : detectedExtension
                let reference = ImageReference(id: UUID(), fileExtension: fileExtension)
                try imageStore.save(data, reference: reference)
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.pendingImageImportID == importID,
                          !self.isClosing,
                          self.mode != .filledText else {
                        // 後発操作で不要になった原本は state に載らないため即時回収する。
                        imageStore.remove(reference)
                        return
                    }
                    self.pendingImageImportID = nil
                    // NSImage は AppKit 境界なのでメインスレッドで作る。拡張子だけ画像でも
                    // 実際にデコードできない場合は保存した原本を破棄して拒否する。
                    guard let displayImage = ImageStore.displayImage(at: imageStore.url(for: reference)) else {
                        imageStore.remove(reference)
                        self.window.shake()
                        return
                    }
                    self.installImage(reference: reference,
                                      displayImage: displayImage,
                                      resizeWindow: true)
                    imageStore.didInstall(reference)
                    self.onStateChanged?()
                }
            } catch {
                NSLog("[Ttemp] 画像の取り込みに失敗した: \(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.pendingImageImportID == importID,
                          !self.isClosing else { return }
                    self.pendingImageImportID = nil
                    self.window.shake()
                }
            }
        }

        // ドロップ先には即時に受理を返し、重いファイルI/Oは上で継続する。
        return true
    }

    private func installImage(reference: ImageReference,
                              displayImage: NSImage,
                              resizeWindow: Bool) {
        imagePayload = ImagePayload(reference: reference,
                                    displayImage: displayImage)

        // 画像モードに入れるのは空のテキストモードからだけなので、それ以前の編集履歴は
        // もう意味がない。残しておくと画像モード中の ⌘Z が隠れたテキストビューに効き、
        // 「画像を削除」した瞬間に消したはずの文字が現れる。
        textView.undoManager?.removeAllActions()

        scrollView.removeFromSuperview()

        let view = imageView ?? makeImageView()
        imageView = view
        view.image = displayImage
        view.frame = window.contentView?.bounds ?? view.frame
        if view.superview == nil {
            window.contentView?.addSubview(view)
        }
        // 入れ替えた領域は明示的に描き直させる（前のビューのピクセルを残さない）
        window.contentView?.needsDisplay = true
        window.makeFirstResponder(view)

        if resizeWindow {
            resizeWindowForImage(pointSize: displayImage.size)
        }
    }

    private func makeImageView() -> NoteImageView {
        let view = NoteImageView(frame: window.contentView?.bounds ?? .zero)
        view.autoresizingMask = [.width, .height]
        view.pasteHandler = self
        view.clipboard = clipboard
        view.onCopy = { [weak self] in self?.copyImageToClipboard() }
        view.menuProvider = { [weak self] in self?.makeImageContextMenu() }
        view.scrollHandler = { [weak self] event in self?.handleScrollWheel(event) ?? false }
        view.onEscape = { [weak self] in self?.requestClose() }
        return view
    }

    /// SPEC §6.2: 画像サイズに合わせてウィンドウをリサイズする（上限60% / 下限200×150）。
    private func resizeWindowForImage(pointSize: CGSize) {
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(origin: .zero, size: CGSize(width: 1440, height: 900))
        let contentSize = ImageWindowSizing.contentSize(forImagePointSize: pointSize,
                                                        visibleFrame: visibleFrame)
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        window.setContentSize(contentSize)

        var frame = window.frame
        frame.origin = CGPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
        frame.origin = WindowPlacement.clamp(frame.origin, size: frame.size, in: visibleFrame)
        window.setFrame(frame, display: true)
    }

    /// SPEC §6.1: 「画像を削除」→ 空のテキストモードに戻る。ウィンドウサイズは維持する（SPEC §6.2）。
    func removeImage() {
        pendingImageImportID = nil
        guard imagePayload != nil else { return }
        imagePayload = nil
        imageView?.image = nil
        imageView?.removeFromSuperview()

        scrollView.frame = window.contentView?.bounds ?? scrollView.frame
        if scrollView.superview == nil {
            window.contentView?.addSubview(scrollView)
        }
        // 入れ替えた領域は明示的に描き直させる（画像のピクセルを残さない）
        window.contentView?.needsDisplay = true
        updateTextViewMinimumHeight()
        // SPEC §7.2: 画像を削除すると、貼る前の文字サイズで復帰する
        applyFontSize()
        window.makeFirstResponder(textView)
        onStateChanged?()
    }

    // MARK: - 画像の操作（SPEC §8.2）

    func copyImageToClipboard() {
        guard let imagePayload else { return }
        var representations: [(Data, NSPasteboard.PasteboardType)] = []
        if let data = imageStore.load(imagePayload.reference),
           let type = UTType(filenameExtension: imagePayload.reference.fileExtension)?.identifier {
            representations.append((data, NSPasteboard.PasteboardType(type)))
        }
        // 原本形式を読めない相手のために TIFF も載せる
        if let tiff = imagePayload.displayImage.tiffRepresentation {
            representations.append((tiff, .tiff))
        }
        // 原本が消えて表示画像の変換にも失敗した場合、既存クリップボードを空にしない。
        guard !representations.isEmpty else { return }
        let pasteboard = clipboard
        pasteboard.clearContents()
        for (data, type) in representations {
            pasteboard.setData(data, forType: type)
        }
    }

    func saveImage(format: ImageExportFormat) {
        guard let imagePayload else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = ImageExporter.defaultFileName(date: Date(),
                                                                  fileExtension: format.fileExtension)
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        // SPEC §8.2: 初期ディレクトリは前回保存した場所
        if let directory = preferences.lastImageSaveDirectory {
            panel.directoryURL = directory
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let reference = imagePayload.reference
            let imageStore = self.imageStore
            // 原本の読込・デコード・再エンコード・書込は巨大画像で重くなるため、
            // 保存先が確定してからバックグラウンドで行う。
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    guard let originalData = imageStore.load(reference),
                          let data = ImageExporter.encode(originalData: originalData, to: format) else {
                        throw ImageSaveError.encodingFailed
                    }
                    try data.write(to: url, options: .atomic)
                    DispatchQueue.main.async { [weak self] in
                        self?.preferences.lastImageSaveDirectory = url.deletingLastPathComponent()
                    }
                } catch {
                    NSLog("[Ttemp] 画像の書き出しに失敗した: \(error.localizedDescription)")
                    DispatchQueue.main.async { [weak self] in self?.window.shake() }
                }
            }
        }
    }

    private enum ImageSaveError: LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            L10n.pick("画像データを指定形式へ変換できませんでした",
                      "The image could not be converted to the selected format")
        }
    }

    /// SPEC §8.2 の右クリックメニュー
    private func makeImageContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.pick("画像をコピー", "Copy Image"),
                     action: #selector(menuCopyImage), keyEquivalent: "").target = self

        let saveItem = menu.addItem(withTitle: L10n.pick("画像を保存", "Save Image"),
                                    action: nil, keyEquivalent: "")
        let saveMenu = NSMenu()
        let formats = ImageExporter.availableFormats(originalExtension: imagePayload?.reference.fileExtension)
        for (index, format) in formats.enumerated() {
            if index == 1, case .original = formats[0] {
                saveMenu.addItem(.separator())
            }
            let item = saveMenu.addItem(withTitle: format.displayName,
                                        action: #selector(menuSaveImage(_:)),
                                        keyEquivalent: "")
            item.target = self
            item.representedObject = FormatBox(format: format)
        }
        saveItem.submenu = saveMenu

        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.pick("画像を削除", "Remove Image"),
                     action: #selector(menuRemoveImage), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let pinItem = menu.addItem(withTitle: L10n.pick("最前面に固定", "Pin on Top"),
                                   action: #selector(menuTogglePin), keyEquivalent: "")
        pinItem.target = self
        pinItem.state = isPinned ? .on : .off
        return menu
    }

    /// `NSMenuItem.representedObject` は `Any?` なので enum を包んで渡す
    private final class FormatBox: NSObject {
        let format: ImageExportFormat
        init(format: ImageExportFormat) { self.format = format }
    }

    @objc private func menuCopyImage() { copyImageToClipboard() }
    @objc private func menuRemoveImage() { removeImage() }
    @objc private func menuTogglePin() { isPinned.toggle() }

    @objc private func menuSaveImage(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? FormatBox else { return }
        saveImage(format: box.format)
    }

    // MARK: - 閉じる

    /// SPEC §4: 閉じる操作。空でなければクリップボードにコピーする。
    func requestClose() {
        guard !isClosing else { return }
        isClosing = true
        pendingImageImportID = nil
        if !isEmpty {
            copyContentsToClipboard()
        }
        // フェード開始前にフォーカスを譲っておく（isClosing 済みなので
        // resignKey 経由の自動消滅とは競合しない）
        onRestoreFocus?()
        fadeOutAndClose()
    }

    /// SPEC §3.2: 空ウィンドウの自動消滅。コピーもフォーカス復帰もしない。
    private func discardSilently() {
        guard !isClosing else { return }
        isClosing = true
        pendingImageImportID = nil
        fadeOutAndClose()
    }

    /// Quit 時など、コピーせずに閉じる（SPEC §4）。
    func closeWithoutCopying() {
        guard !isClosing else { return }
        isClosing = true
        pendingImageImportID = nil
        window.close()
    }

    private func copyContentsToClipboard() {
        // SPEC §4: 空のときは一切変更しない（呼び出し側で保証）
        if imagePayload != nil {
            copyImageToClipboard()
            return
        }
        let pasteboard = clipboard
        pasteboard.clearContents()
        pasteboard.setString(textView.string, forType: .string)
    }

    private func fadeOutAndClose() {
        window.fade(to: 0, duration: Self.fadeDuration) { [weak self] in
            guard let self else { return }
            self.window.close()
            self.onClosed?(self)
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 閉じるボタン / ⌘W はここを通る。コピー＋フェードアウトを挟むため一旦拒否する。
        if isClosing { return true }
        requestClose()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        // シートを出すと親ウィンドウは key を失う。ここで破棄すると、右クリックの
        // 「画像を選択…」（＝空のテキストモードでしか出ない）を選んだ瞬間に、
        // シートを付けたままウィンドウが閉じることになる。
        guard window.attachedSheet == nil else { return }
        // 受理済みの画像ファイルをバックグラウンド保存中は、見かけ上まだ空でも閉じない。
        guard pendingImageImportID == nil else { return }
        // SPEC §3.2: キーウィンドウでなくなった時点で判定する。空・テキストモードのときだけ破棄する。
        // ピン留め中は原則として残すが、設定が「空なら閉じる」なら空は消す（SPEC §9）。
        guard !isClosing, isEmpty else { return }
        guard !isPinned || preferences.newWindowPinMode.dismissesEmptyWhilePinned else { return }
        discardSilently()
    }

    func windowDidMove(_ notification: Notification) {
        onStateChanged?()
    }

    func windowDidResize(_ notification: Notification) {
        onStateChanged?()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        // ドラッグ中は省いた厳密な高さ合わせをここで一度だけ行う
        // （縮めたときに、テキストより下の空白をスクロールできてしまうのを防ぐ）
        textView.sizeToFit()
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView,
                  shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        let accepted = PlainTextSanitizer.canReplace(currentUTF16Length: textView.textStorage?.length ?? 0,
                                                     range: affectedCharRange,
                                                     replacement: replacementString)
        if !accepted { window.shake() }
        return accepted
    }

    func textDidChange(_ notification: Notification) {
        // 空ウィンドウへの画像取り込み中にユーザーが入力したら、文字を優先する。
        pendingImageImportID = nil
        onStateChanged?()
    }
}
