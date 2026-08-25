import Foundation

/// `state.json` の保存・読込・デバウンス・破損処理（SPEC §10）。
final class StateStore {
    static let maximumNoteCount = 32
    static let maximumStateFileByteCount = 64 * 1_024 * 1_024

    private enum StateValidationError: Error {
        case invalidFile
        case fileTooLarge
        case tooManyNotes
        case duplicateNoteID
        case invalidText
        case invalidFrame
    }

    enum LoadResult: Equatable {
        /// 正常に読めた
        case loaded(AppState)
        /// ファイルが存在しない（初回起動）
        case empty
        /// 読めなかったので退避した。復元は諦めて空で起動する（SPEC §10.4）
        case recovered(backupURL: URL)
    }

    /// SPEC §10.1: 逐次保存は1秒程度のデバウンス
    static let defaultDebounceInterval: TimeInterval = 1.0
    /// 変更が途切れなくても、最初の未保存の変更からこの時間内には必ず書き出す。
    ///
    /// 純粋なデバウンスだと、タイピングやウィンドウのドラッグが1秒以上途切れずに
    /// 続いている間は保存が先送りされ続ける（毎回タイマーを張り直すため）。
    /// その間にクラッシュや強制終了が起きると変更が丸ごと失われるので、上限を設ける。
    static let defaultMaxSaveDelay: TimeInterval = 5.0

    let directory: URL
    private let debounceInterval: TimeInterval
    private let maxSaveDelay: TimeInterval
    private let fileManager: FileManager
    private let uptimeProvider: () -> TimeInterval
    /// JSON エンコード、ファイル書き込み、画像ディレクトリ走査を直列化する。
    /// ノート本文が大きくても AppKit のメインスレッドを止めない。
    private let ioQueue = DispatchQueue(label: "com.am921.ttemp.state-store", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private var retrySave: DispatchWorkItem?
    /// 未保存の変更のうち、いちばん古いものが積まれた時刻
    private var oldestPendingChangeUptime: TimeInterval?
    /// 状態ファイルを読めなかったセッションでは孤児画像の掃除をしない。
    /// 復元できなかっただけで、退避した state.json から手で拾える可能性を残すため（SPEC §10.4）。
    private var allowsImagePruning = true
    /// 前回 prune 時に参照されていた画像ファイル名。参照集合が変わらない限り
    /// ディレクトリ走査を繰り返さない（タイピング中の1秒ごとの保存で I/O しないため）。
    private var lastPrunedReferences: Set<String>?

    /// 保存すべき状態を返すクロージャ。`scheduleSave()` / `flush()` の時点で評価される。
    var snapshotProvider: (() -> AppState)?

    init(directory: URL = StateStore.defaultDirectory,
         debounceInterval: TimeInterval = StateStore.defaultDebounceInterval,
         maxSaveDelay: TimeInterval = StateStore.defaultMaxSaveDelay,
         fileManager: FileManager = .default,
         uptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.directory = directory
        self.debounceInterval = max(0, debounceInterval)
        self.maxSaveDelay = max(0, maxSaveDelay)
        self.fileManager = fileManager
        self.uptimeProvider = uptimeProvider
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ttemp", isDirectory: true)
    }

    var stateFileURL: URL { directory.appendingPathComponent("state.json") }
    var imagesDirectoryURL: URL { directory.appendingPathComponent("Images", isDirectory: true) }

    // MARK: - 読込

    func load() -> LoadResult {
        ioQueue.sync { loadSynchronously() }
    }

    private func loadSynchronously() -> LoadResult {
        guard fileManager.fileExists(atPath: stateFileURL.path) else { return .empty }

        do {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            let values = try stateFileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw StateValidationError.invalidFile
            }
            guard let fileSize = values.fileSize,
                  fileSize >= 0,
                  fileSize <= Self.maximumStateFileByteCount else {
                throw StateValidationError.fileTooLarge
            }
            let handle = try FileHandle(forReadingFrom: stateFileURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumStateFileByteCount + 1) ?? Data()
            guard data.count <= Self.maximumStateFileByteCount else {
                throw StateValidationError.fileTooLarge
            }
            let state = try JSONDecoder().decode(AppState.self, from: data)
            guard state.version == AppState.currentVersion else {
                // 未知のバージョンは解釈できない。上書きせず退避する。
                allowsImagePruning = false
                return .recovered(backupURL: try quarantineStateFile(reason: "version-\(state.version)"))
            }
            try Self.validate(state)
            return .loaded(state)
        } catch {
            NSLog("[Ttemp] state.json を読めなかった: \(error.localizedDescription)")
            allowsImagePruning = false
            let reason = error is StateValidationError ? "invalid" : "corrupt"
            if let backup = try? quarantineStateFile(reason: reason) {
                return .recovered(backupURL: backup)
            }
            return .empty
        }
    }

    /// SPEC §10.4: 壊れたファイルは `state.json.corrupt-<日時>` にリネームして残す。
    private func quarantineStateFile(reason: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())
        var backup = directory.appendingPathComponent("state.json.\(reason)-\(stamp)")
        var suffix = 2
        while fileManager.fileExists(atPath: backup.path) {
            backup = directory.appendingPathComponent("state.json.\(reason)-\(stamp)-\(suffix)")
            suffix += 1
        }
        try fileManager.moveItem(at: stateFileURL, to: backup)
        NSLog("[Ttemp] 読めなかった state.json を退避した: \(backup.lastPathComponent)")
        return backup
    }

    // MARK: - 保存

    /// SPEC §10.1: 内容変更・移動・リサイズのたびに呼ぶ。1秒デバウンスで実際の書き込みを行う。
    /// ただし変更が途切れない場合でも `maxSaveDelay` で頭打ちにする。
    func scheduleSave() {
        retrySave?.cancel()
        retrySave = nil

        let delay: TimeInterval
        if let oldest = oldestPendingChangeUptime {
            // 最初の未保存の変更からの経過時間で頭打ちにする
            // 壁時計はユーザー操作や時刻同期で前後するため、単調増加する uptime を使う。
            let remaining = maxSaveDelay - (uptimeProvider() - oldest)
            delay = max(0, min(debounceInterval, remaining))
        } else {
            oldestPendingChangeUptime = uptimeProvider()
            delay = debounceInterval
        }

        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performSave()
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// 保留中の保存を即座に書き出す（Quit 時。SPEC §10.1）。
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        retrySave?.cancel()
        retrySave = nil
        oldestPendingChangeUptime = nil
        guard let state = snapshotProvider?() else { return }
        do {
            try ioQueue.sync { try saveSynchronously(state) }
        } catch {
            NSLog("[Ttemp] state.json の保存に失敗した: \(error.localizedDescription)")
        }
    }

    private func performSave() {
        pendingSave = nil
        oldestPendingChangeUptime = nil
        guard let state = snapshotProvider?() else { return }
        ioQueue.async { [self] in
            do {
                try saveSynchronously(state)
            } catch {
                NSLog("[Ttemp] state.json の保存に失敗した: \(error.localizedDescription)")
                scheduleRetryAfterFailure()
            }
        }
    }

    func save(_ state: AppState) throws {
        try ioQueue.sync { try saveSynchronously(state) }
    }

    private func saveSynchronously(_ state: AppState) throws {
        try Self.validate(state)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= Self.maximumStateFileByteCount else {
            throw StateValidationError.fileTooLarge
        }
        // SPEC §10.4: アトミック書き込み（一時ファイルに書いてから rename）
        try data.write(to: stateFileURL, options: .atomic)
        // state.json を書いた後にだけ孤児画像を掃除する（順序を逆にすると
        // 保存に失敗した場合に参照されている画像を消してしまう）
        pruneUnreferencedImages(keeping: state)
    }

    private static func validate(_ state: AppState) throws {
        guard state.notes.count <= maximumNoteCount else {
            throw StateValidationError.tooManyNotes
        }
        guard Set(state.notes.map(\.id)).count == state.notes.count else {
            throw StateValidationError.duplicateNoteID
        }
        for note in state.notes {
            let frame = note.frame
            guard frame.x.isFinite,
                  frame.y.isFinite,
                  frame.width.isFinite,
                  frame.height.isFinite else { throw StateValidationError.invalidFrame }
            if case .text(let text) = note.content,
               !PlainTextSanitizer.isWithinStorageLimit(text) {
                throw StateValidationError.invalidText
            }
        }
    }

    /// 一時的なディスク障害で最後の変更が保存されないまま止まらないよう再試行する。
    /// 新しい編集が来た場合は通常のデバウンスがこの再試行を置き換える。
    private func scheduleRetryAfterFailure() {
        DispatchQueue.main.async { [weak self] in
            guard let self, pendingSave == nil, retrySave == nil else { return }
            let item = DispatchWorkItem { [weak self] in
                self?.retrySave = nil
                self?.scheduleSave()
            }
            retrySave = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.defaultMaxSaveDelay,
                                          execute: item)
        }
    }

    // MARK: - 画像ファイル

    /// state から参照されていない画像ファイルを削除する。
    /// 孤児が生まれるのは参照集合が変わる保存（画像の追加・置換・ウィンドウの削除）と
    /// 前セッションのクラッシュ残骸だけなので、集合が同じ間はスキップできる
    /// （セッション最初の保存は `lastPrunedReferences == nil` で必ず走る）。
    private func pruneUnreferencedImages(keeping state: AppState) {
        guard allowsImagePruning else { return }
        let referenced = Set(state.notes.compactMap { note -> String? in
            guard case .image(let reference) = note.content else { return nil }
            return reference.fileName
        })
        guard referenced != lastPrunedReferences else { return }

        guard fileManager.fileExists(atPath: imagesDirectoryURL.path) else {
            lastPrunedReferences = referenced
            return
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(at: imagesDirectoryURL,
                                                          includingPropertiesForKeys: keys)
        } catch {
            NSLog("[Ttemp] 孤児画像の一覧取得に失敗した: \(error.localizedDescription)")
            return
        }

        var completedWithoutError = true
        for entry in entries {
            let name = entry.lastPathComponent
            guard ImageReference.isManagedFileName(name), !referenced.contains(name) else { continue }
            do {
                let values = try entry.resourceValues(forKeys: Set(keys))
                // 管理形式と同名でもディレクトリは再帰削除しない。通常ファイルと
                // シンボリックリンク（リンク自体の削除）だけを掃除する。
                guard values.isRegularFile == true || values.isSymbolicLink == true else { continue }
                try fileManager.removeItem(at: entry)
            } catch {
                completedWithoutError = false
                NSLog("[Ttemp] 孤児画像の削除に失敗した (\(name)): \(error.localizedDescription)")
            }
        }
        if completedWithoutError {
            lastPrunedReferences = referenced
        }
    }
}
