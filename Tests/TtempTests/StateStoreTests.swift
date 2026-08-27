import XCTest

/// SPEC §10 の永続化のテスト。
final class StateStoreTests: XCTestCase {
    private var directory: URL!
    private var store: StateStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TtempStateStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = StateStore(directory: directory, debounceInterval: 0.05)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeNote(text: String = "hello",
                          frame: CGRect = CGRect(x: 10, y: 20, width: 480, height: 320),
                          isPinned: Bool = false,
                          offset: Double = 0) -> NoteSnapshot {
        NoteSnapshot(id: UUID(),
                     content: .text(text),
                     frame: FrameSnapshot(frame),
                     isPinned: isPinned,
                     fontSizeOffset: offset)
    }

    // MARK: - シリアライズ / デシリアライズ

    func test_保存した状態をそのまま読み戻せる() throws {
        let state = AppState(notes: [
            makeNote(text: "一枚目\nタブ\tと絵文字🍣", isPinned: true, offset: 3),
            makeNote(text: "二枚目", frame: CGRect(x: -100, y: 50, width: 640, height: 400), offset: -2),
        ])
        try store.save(state)

        XCTAssertEqual(store.load(), .loaded(state))
    }

    func test_画像参照を含む状態を読み戻せる() throws {
        let reference = ImageReference(id: UUID(), fileExtension: "gif")
        let note = NoteSnapshot(id: UUID(),
                                content: .image(reference),
                                frame: FrameSnapshot(CGRect(x: 0, y: 0, width: 300, height: 200)),
                                isPinned: false,
                                fontSizeOffset: 5)
        try store.save(AppState(notes: [note]))

        guard case .loaded(let loaded) = store.load() else { return XCTFail("読み込みに失敗") }
        XCTAssertEqual(loaded.notes.first?.content, .image(reference))
        // SPEC §7.2: 画像モード中もオフセットは保持される
        XCTAssertEqual(loaded.notes.first?.fontSizeOffset, 5)
    }

    func test_画像拡張子を安全なファイル名へ正規化する() throws {
        let id = UUID()
        XCTAssertEqual(ImageReference(id: id, fileExtension: "PNG").fileExtension, "png")
        XCTAssertEqual(ImageReference(id: id, fileExtension: "../../secret").fileExtension, "dat")
        XCTAssertEqual(ImageReference(id: id, fileExtension: "a-b").fileExtension, "dat")
        XCTAssertEqual(ImageReference(id: id, fileExtension: String(repeating: "a", count: 17)).fileExtension,
                       "dat")

        let json = Data(#"{"id":"\#(id.uuidString)","fileExtension":"../png"}"#.utf8)
        let decoded = try JSONDecoder().decode(ImageReference.self, from: json)
        XCTAssertEqual(decoded.fileName, "\(id.uuidString).dat")
        XCTAssertFalse(decoded.fileName.contains("/"))
    }

    func test_管理対象の画像ファイル名だけを識別する() {
        let id = UUID().uuidString
        XCTAssertTrue(ImageReference.isManagedFileName("\(id).png"))
        XCTAssertFalse(ImageReference.isManagedFileName("\(id).PNG"))
        XCTAssertFalse(ImageReference.isManagedFileName("\(id).../png"))
        XCTAssertFalse(ImageReference.isManagedFileName("README.txt"))
    }

    func test_ノードの並び順が保たれる() throws {
        let notes = (0..<5).map { makeNote(text: "note-\($0)") }
        try store.save(AppState(notes: notes))

        guard case .loaded(let loaded) = store.load() else { return XCTFail("読み込みに失敗") }
        XCTAssertEqual(loaded.notes.map(\.id), notes.map(\.id))
    }

    func test_クランプ範囲外のオフセットもそのまま保存される() throws {
        // SPEC §7.1: クランプは表示時のみ。オフセット値自体は保持する
        try store.save(AppState(notes: [makeNote(offset: 999)]))
        guard case .loaded(let loaded) = store.load() else { return XCTFail("読み込みに失敗") }
        XCTAssertEqual(loaded.notes.first?.fontSizeOffset, 999)
    }

    // MARK: - 初回起動・破損

    func test_ファイルがなければemptyを返す() {
        XCTAssertEqual(store.load(), .empty)
    }

    func test_壊れたファイルは退避され空で起動する() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let broken = Data("{ this is not json".utf8)
        try broken.write(to: store.stateFileURL)

        guard case .recovered(let backupURL) = store.load() else {
            return XCTFail("recovered が返るべき")
        }
        // SPEC §10.4: 壊れたファイルは残す。元の内容も失わない
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("state.json.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: backupURL), broken)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateFileURL.path))
    }

    func test_未知のスキーマバージョンは退避される() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let future = Data(#"{"version":999,"notes":[]}"#.utf8)
        try future.write(to: store.stateFileURL)

        guard case .recovered(let backupURL) = store.load() else {
            return XCTFail("recovered が返るべき")
        }
        XCTAssertTrue(backupURL.lastPathComponent.contains("version-999"))
        XCTAssertEqual(try Data(contentsOf: backupURL), future)
    }

    func test_上限を超える本文は退避される() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = String(repeating: "a", count: PlainTextSanitizer.maximumUTF16Length + 1)
        let data = try JSONEncoder().encode(AppState(notes: [makeNote(text: text)]))
        try data.write(to: store.stateFileURL)

        guard case .recovered(let backupURL) = store.load() else {
            return XCTFail("recovered が返るべき")
        }
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("state.json.invalid-"))
    }

    func test_ノート数上限を超える状態は読み込みも保存も拒否する() throws {
        let state = AppState(notes: (0...StateStore.maximumNoteCount).map {
            makeNote(text: "note-\($0)")
        })
        XCTAssertThrowsError(try store.save(state))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: store.stateFileURL)
        guard case .recovered(let backupURL) = store.load() else {
            return XCTFail("recovered が返るべき")
        }
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("state.json.invalid-"))
    }

    func test_重複したノートIDは退避される() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let note = makeNote()
        try JSONEncoder().encode(AppState(notes: [note, note])).write(to: store.stateFileURL)

        guard case .recovered(let backupURL) = store.load() else {
            return XCTFail("recovered が返るべき")
        }
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("state.json.invalid-"))
    }

    func test_巨大なstateファイルは内容を読む前に退避される() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: store.stateFileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: store.stateFileURL)
        try handle.truncate(atOffset: UInt64(StateStore.maximumStateFileByteCount + 1))
        try handle.close()

        guard case .recovered(let backupURL) = store.load() else {
            return XCTFail("recovered が返るべき")
        }
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("state.json.invalid-"))
        let size = try backupURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        XCTAssertEqual(size, StateStore.maximumStateFileByteCount + 1)
    }

    func test_退避先が既にあっても上書きしない() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken-1".utf8).write(to: store.stateFileURL)
        guard case .recovered(let first) = store.load() else { return XCTFail("recovered が返るべき") }

        try Data("broken-2".utf8).write(to: store.stateFileURL)
        guard case .recovered(let second) = store.load() else { return XCTFail("recovered が返るべき") }

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), Data("broken-1".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("broken-2".utf8))
    }

    // MARK: - デバウンス

    func test_連続した保存要求は1回にまとまる() {
        var callCount = 0
        store.snapshotProvider = {
            callCount += 1
            return AppState()
        }
        for _ in 0..<10 {
            store.scheduleSave()
        }
        XCTAssertEqual(callCount, 0, "デバウンス中は書き込まない")

        let expectation = expectation(description: "debounced save")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.stateFileURL.path))
    }

    func test_変更が途切れなくても最大遅延で必ず保存される() {
        // 純粋なデバウンスだと、デバウンス間隔より短い周期で変更が続く限り
        // 保存は永久に先送りされる。その間のクラッシュで全部失うのを防ぐ。
        let store = StateStore(directory: directory, debounceInterval: 0.1, maxSaveDelay: 0.25)
        var callCount = 0
        store.snapshotProvider = {
            callCount += 1
            return AppState()
        }

        // 0.05秒ごと（デバウンス間隔より短い）に 0.75秒間ずっと変更を出し続ける
        for step in 0..<16 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.05) {
                store.scheduleSave()
            }
        }

        // まだ変更が流れている最中に確認するのが要点。ここを変更が止まったあとに
        // すると、純粋なデバウンスでも保存されてしまい退行を検出できない。
        var midStreamCount = 0
        let expectation = expectation(description: "max delay save")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            midStreamCount = callCount
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)

        XCTAssertGreaterThanOrEqual(midStreamCount, 1, "変更が途切れない間も最大遅延で書き出されること")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.stateFileURL.path))
    }

    func test_保存後は最大遅延の起点がリセットされる() {
        let store = StateStore(directory: directory, debounceInterval: 0.05, maxSaveDelay: 0.2)
        var callCount = 0
        store.snapshotProvider = {
            callCount += 1
            return AppState()
        }
        // 1回保存させてから、単発の変更が最大遅延ではなくデバウンス間隔で書かれること
        store.scheduleSave()
        let first = expectation(description: "first save")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { first.fulfill() }
        wait(for: [first], timeout: 2)
        XCTAssertEqual(callCount, 1)

        store.scheduleSave()
        let second = expectation(description: "second save")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { second.fulfill() }
        wait(for: [second], timeout: 2)
        XCTAssertEqual(callCount, 2, "起点がリセットされ、次もデバウンス間隔で書かれる")
    }

    func test_最大保存遅延は壁時計ではなく単調時刻で判定する() {
        var uptime = 100.0
        let store = StateStore(directory: directory,
                               debounceInterval: 10,
                               maxSaveDelay: 5,
                               uptimeProvider: { uptime })
        var callCount = 0
        store.snapshotProvider = {
            callCount += 1
            return AppState()
        }

        store.scheduleSave()
        uptime = 106
        store.scheduleSave()

        let expectation = expectation(description: "monotonic max delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(callCount, 1)
    }

    func test_flushは保留中の保存を即座に書き出す() {
        store.snapshotProvider = { AppState(notes: [self.makeNote(text: "flush")]) }
        store.scheduleSave()
        store.flush()

        guard case .loaded(let loaded) = store.load() else { return XCTFail("読み込みに失敗") }
        XCTAssertEqual(loaded.notes.count, 1)
    }

    func test_flush後に保留分が二重に書かれない() {
        var callCount = 0
        store.snapshotProvider = {
            callCount += 1
            return AppState()
        }
        store.scheduleSave()
        store.flush()

        let expectation = expectation(description: "no extra save")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - 画像ファイルの掃除

    func test_取り込み中の画像は以前のスナップショットの保存で削除しない() throws {
        let images = ImageStore(directory: store.imagesDirectoryURL, pendingImports: store.pendingImageImports)
        let pending = ImageReference(id: UUID(), fileExtension: "png")
        try images.save(Data("pending".utf8), reference: pending)
        // A background import has written the original, but the main-thread
        // completion has not yet installed its reference into a note.
        try store.save(AppState())
        XCTAssertNotNil(images.load(pending))
        let note = NoteSnapshot(id: UUID(), content: .image(pending), frame: FrameSnapshot(.zero),
                                isPinned: false, fontSizeOffset: 0)
        try store.save(AppState(notes: [note]))
        XCTAssertNotNil(images.load(pending))
        try store.save(AppState())
        XCTAssertNil(images.load(pending), "A committed, then closed image must still be pruned")
    }

    func test_取り込みをキャンセルすると原本と保護を解除する() throws {
        let images = ImageStore(directory: store.imagesDirectoryURL, pendingImports: store.pendingImageImports)
        let pending = ImageReference(id: UUID(), fileExtension: "png")
        try images.save(Data("pending".utf8), reference: pending)
        images.remove(pending)
        XCTAssertNil(images.load(pending))
        store.pendingImageImports.whilePruning(releasing: []) { XCTAssertTrue($0.isEmpty) }
    }

    func test_画像を最初の保存より前に閉じても孤児を回収する() throws {
        let images = ImageStore(directory: store.imagesDirectoryURL, pendingImports: store.pendingImageImports)
        let reference = ImageReference(id: UUID(), fileExtension: "png")
        try images.save(Data("pending".utf8), reference: reference)
        try store.save(AppState())
        XCTAssertNotNil(images.load(reference))
        images.didInstall(reference)
        // The window is closed before any state containing the image is saved.
        try store.save(AppState())
        XCTAssertNil(images.load(reference))
    }

    func test_古いスナップショットは後から取り込まれた画像の保護を解除しない() {
        let imports = store.pendingImageImports
        let reference = ImageReference(id: UUID(), fileExtension: "png")
        imports.protect(reference)
        let oldSnapshot = imports.installedBeforeSnapshot()
        imports.didInstall(reference)
        imports.whilePruning(releasing: oldSnapshot) { XCTAssertTrue($0.contains(reference.fileName)) }
        let newSnapshot = imports.installedBeforeSnapshot()
        imports.whilePruning(releasing: newSnapshot) { XCTAssertTrue($0.isEmpty) }
    }

    func test_保存失敗では取り込み済み画像の保護を解除しない() throws {
        let images = ImageStore(directory: store.imagesDirectoryURL, pendingImports: store.pendingImageImports)
        let reference = ImageReference(id: UUID(), fileExtension: "png")
        try images.save(Data("pending".utf8), reference: reference)
        images.didInstall(reference)
        let duplicate = makeNote()
        XCTAssertThrowsError(try store.save(AppState(notes: [duplicate, duplicate])))
        store.pendingImageImports.whilePruning(releasing: []) { XCTAssertTrue($0.contains(reference.fileName)) }
        XCTAssertNotNil(images.load(reference))
        try store.save(AppState())
        XCTAssertNil(images.load(reference))
    }

    func test_参照されていない画像ファイルは削除される() throws {
        let kept = ImageReference(id: UUID(), fileExtension: "png")
        let orphan = ImageReference(id: UUID(), fileExtension: "png")
        try FileManager.default.createDirectory(at: store.imagesDirectoryURL, withIntermediateDirectories: true)
        for reference in [kept, orphan] {
            try Data("x".utf8).write(to: store.imagesDirectoryURL.appendingPathComponent(reference.fileName))
        }

        let note = NoteSnapshot(id: UUID(),
                                content: .image(kept),
                                frame: FrameSnapshot(.zero),
                                isPinned: false,
                                fontSizeOffset: 0)
        try store.save(AppState(notes: [note]))

        let remaining = try FileManager.default.contentsOfDirectory(at: store.imagesDirectoryURL,
                                                                   includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
        XCTAssertEqual(remaining, [kept.fileName])
    }

    func test_参照集合が変わらない保存では掃除しない() throws {
        // タイピング中の1秒ごとの保存で毎回ディレクトリを走査しないための挙動。
        // 孤児は参照集合が変わる保存か、次セッション最初の保存で回収される。
        let kept = ImageReference(id: UUID(), fileExtension: "png")
        try FileManager.default.createDirectory(at: store.imagesDirectoryURL, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: store.imagesDirectoryURL.appendingPathComponent(kept.fileName))
        let note = NoteSnapshot(id: UUID(),
                                content: .image(kept),
                                frame: FrameSnapshot(.zero),
                                isPinned: false,
                                fontSizeOffset: 0)
        try store.save(AppState(notes: [note]))

        // 1回目の保存の後に現れた孤児は、同じ参照集合の保存では消えない
        let orphan = ImageReference(id: UUID(), fileExtension: "png")
        let orphanURL = store.imagesDirectoryURL.appendingPathComponent(orphan.fileName)
        try Data("x".utf8).write(to: orphanURL)
        try store.save(AppState(notes: [note]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanURL.path))

        // 参照集合が変わる保存では掃除される
        try store.save(AppState())
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
    }

    func test_状態ファイルを読めなかったセッションでは画像を消さない() throws {
        // 復元できなかっただけで、退避した state.json から手で拾える可能性を残す
        try FileManager.default.createDirectory(at: store.imagesDirectoryURL, withIntermediateDirectories: true)
        let orphan = ImageReference(id: UUID(), fileExtension: "png")
        try Data("x".utf8).write(to: store.imagesDirectoryURL.appendingPathComponent(orphan.fileName))
        try Data("{ broken".utf8).write(to: store.stateFileURL)

        guard case .recovered = store.load() else { return XCTFail("recovered が返るべき") }
        try store.save(AppState())

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.imagesDirectoryURL.appendingPathComponent(orphan.fileName).path))
    }

    func test_孤児掃除は無関係なファイルやディレクトリを消さない() throws {
        try FileManager.default.createDirectory(at: store.imagesDirectoryURL,
                                                withIntermediateDirectories: true)
        let unmanagedURL = store.imagesDirectoryURL.appendingPathComponent("README.txt")
        try Data("keep".utf8).write(to: unmanagedURL)

        let directoryName = ImageReference(id: UUID(), fileExtension: "png").fileName
        let nestedDirectoryURL = store.imagesDirectoryURL.appendingPathComponent(directoryName,
                                                                                  isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectoryURL,
                                                withIntermediateDirectories: true)

        let orphan = ImageReference(id: UUID(), fileExtension: "png")
        let orphanURL = store.imagesDirectoryURL.appendingPathComponent(orphan.fileName)
        try Data("remove".utf8).write(to: orphanURL)

        try store.save(AppState())

        XCTAssertTrue(FileManager.default.fileExists(atPath: unmanagedURL.path))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedDirectoryURL.path,
                                                      isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
    }
}
