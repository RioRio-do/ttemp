import Foundation

/// State-store I/O is serialized. A narrow interface lets tests inject failures
/// without inheriting FileManager's SDK-dependent Sendable annotations.
protocol StateFileManaging {
    func fileExists(atPath path: String) -> Bool
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
                             options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL]
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                         attributes: [FileAttributeKey: Any]?) throws
    func removeItem(at url: URL) throws
}

extension FileManager: StateFileManaging {}

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
    let pendingImageImports = PendingImageImports()
    private let debounceInterval: TimeInterval
    private let maxSaveDelay: TimeInterval
    private let fileManager: any StateFileManaging
    private let uptimeProvider: () -> TimeInterval
    /// JSON エンコード、ファイル書き込み、画像ディレクトリ走査を直列化する。
    /// ノート本文が大きくても AppKit のメインスレッドを止めない。
    private let ioQueue = DispatchQueue(label: "com.am921.ttemp.state-store", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private var retrySave: DispatchWorkItem?
    /// 未保存の変更のうち、いちばん古いものが積まれた時刻
    private var oldestPendingChangeUptime: TimeInterval?
    /// 退避した状態が残る間は、再起動後も復旧用の画像を掃除しない（SPEC §10.4）。
    private var allowsImagePruning = true
    private var hasCheckedRecoveryBackups = false
    /// An unreadable state must reach a backup before any new state replaces it.
    private var pendingQuarantineReason: String?
    /// 前回 prune 時に参照されていた画像ファイル名。参照・取り込み保護集合が変わらない限り
    /// ディレクトリ走査を繰り返さない（タイピング中の1秒ごとの保存で I/O しないため）。
    private var lastPrunedReferences: Set<String>?
    private var lastPrunedProtected: Set<String>?

    /// 保存すべき状態を返すクロージャ。`scheduleSave()` / `flush()` の時点で評価される。
    var snapshotProvider: (() -> AppState)?

    init(directory: URL = StateStore.defaultDirectory,
         debounceInterval: TimeInterval = StateStore.defaultDebounceInterval,
         maxSaveDelay: TimeInterval = StateStore.defaultMaxSaveDelay,
         fileManager: any StateFileManaging = FileManager.default,
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
#if DEBUG
        // The separate Debug bundle can run alongside production; never share its notes.
        return base.appendingPathComponent("Ttemp Development", isDirectory: true)
#else
        return base.appendingPathComponent("Ttemp", isDirectory: true)
#endif
    }

    var stateFileURL: URL { directory.appendingPathComponent("state.json") }
    var imagesDirectoryURL: URL { directory.appendingPathComponent("Images", isDirectory: true) }

    // MARK: - 読込

    func load() -> LoadResult {
        ioQueue.sync { loadSynchronously() }
    }

    private func loadSynchronously() -> LoadResult {
        checkRecoveryBackupsIfNeeded()

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
                return recoverStateFile(reason: "version-\(state.version)")
            }
            try Self.validate(state)
            return .loaded(state)
        } catch {
            // fileExists also returns false for access failures. Only an actual
            // missing-file error is an empty installation; preserve other failures.
            if Self.isMissingFileError(error) { return .empty }
            NSLog("[Ttemp] state.json を読めなかった: \(error.localizedDescription)")
            let reason = error is StateValidationError ? "invalid" : "corrupt"
            return recoverStateFile(reason: reason)
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
    }

    private func recoverStateFile(reason: String) -> LoadResult {
        allowsImagePruning = false
        pendingQuarantineReason = reason
        do {
            let backup = try quarantineStateFile(reason: reason)
            pendingQuarantineReason = nil
            return .recovered(backupURL: backup)
        } catch {
            NSLog("[Ttemp] 状態を退避できないため元データを保持する: \(error.localizedDescription)")
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

    /// Check once per store, on the serialized I/O queue, including when the
    /// current state is absent or valid. An older quarantine can still reference
    /// originals that are missing from the new state. Never guess on I/O failure.
    private func checkRecoveryBackupsIfNeeded() {
        guard !hasCheckedRecoveryBackups else { return }
        hasCheckedRecoveryBackups = true
        do {
            let entries = try fileManager.contentsOfDirectory(at: directory,
                                                               includingPropertiesForKeys: nil, options: [])
            let prefixes = ["state.json.corrupt-", "state.json.invalid-", "state.json.version-"]
            if entries.contains(where: { entry in
                prefixes.contains(where: { entry.lastPathComponent.hasPrefix($0) })
            }) {
                allowsImagePruning = false
            }
        } catch {
            // A new installation has no directory yet. Other failures cannot
            // establish that recovery backups are absent, so preserve images.
            if !Self.isMissingFileError(error) {
                allowsImagePruning = false
                NSLog("[Ttemp] 復旧データを確認できないため画像の掃除を停止した: \(error.localizedDescription)")
            }
        }
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
        let completedImports = pendingImageImports.installedBeforeSnapshot()
        do {
            try ioQueue.sync { try saveSynchronously(state, completedImports: completedImports) }
        } catch {
            NSLog("[Ttemp] state.json の保存に失敗した: \(error.localizedDescription)")
        }
    }

    private func performSave() {
        pendingSave = nil
        oldestPendingChangeUptime = nil
        guard let state = snapshotProvider?() else { return }
        let completedImports = pendingImageImports.installedBeforeSnapshot()
        ioQueue.async { [self] in
            do {
                try saveSynchronously(state, completedImports: completedImports)
            } catch {
                NSLog("[Ttemp] state.json の保存に失敗した: \(error.localizedDescription)")
                scheduleRetryAfterFailure()
            }
        }
    }

    func save(_ state: AppState) throws {
        let completedImports = pendingImageImports.installedBeforeSnapshot()
        try ioQueue.sync { try saveSynchronously(state, completedImports: completedImports) }
    }

    private func saveSynchronously(_ state: AppState, completedImports: Set<String>) throws {
        checkRecoveryBackupsIfNeeded()
        try Self.validate(state)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= Self.maximumStateFileByteCount else {
            throw StateValidationError.fileTooLarge
        }
        if let reason = pendingQuarantineReason {
            // A temporary permission/disk failure during load must not turn the
            // next successful write into irreversible loss of the original.
            // Retry the backup first; normal save retry handles continued failure.
            do {
                _ = try quarantineStateFile(reason: reason)
            } catch {
                guard Self.isMissingFileError(error) else { throw error }
                // The original may have been moved away for manual recovery.
            }
            pendingQuarantineReason = nil
        }
        // SPEC §10.4: アトミック書き込み（一時ファイルに書いてから rename）
        try data.write(to: stateFileURL, options: .atomic)
        // state.json を書いた後にだけ孤児画像を掃除する（順序を逆にすると
        // 保存に失敗した場合に参照されている画像を消してしまう）
        pruneUnreferencedImages(keeping: state, completedImports: completedImports)
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
    /// 前セッションのクラッシュ残骸だけなので、参照・保護集合が同じ間はスキップできる
    /// （セッション最初の保存は `lastPrunedReferences == nil` で必ず走る）。
    private func pruneUnreferencedImages(keeping state: AppState, completedImports: Set<String>) {
        let referenced = Set(state.notes.compactMap { note -> String? in
            guard case .image(let reference) = note.content else { return nil }
            return reference.fileName
        })
        pendingImageImports.whilePruning(releasing: completedImports.union(referenced)) { protected in
            // Completed imports no longer need in-memory protection even when
            // quarantined state prevents any deletion for this session.
            guard allowsImagePruning else { return }
            pruneUnreferencedImages(referenced: referenced, protected: protected)
        }
    }

    private func pruneUnreferencedImages(referenced: Set<String>, protected: Set<String>) {
        guard referenced != lastPrunedReferences || protected != lastPrunedProtected else { return }

        guard fileManager.fileExists(atPath: imagesDirectoryURL.path) else {
            lastPrunedReferences = referenced
            lastPrunedProtected = protected
            return
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(at: imagesDirectoryURL,
                                                          includingPropertiesForKeys: keys, options: [])
        } catch {
            NSLog("[Ttemp] 孤児画像の一覧取得に失敗した: \(error.localizedDescription)")
            return
        }

        var completedWithoutError = true
        for entry in entries {
            let name = entry.lastPathComponent
            guard ImageReference.isManagedFileName(name), !referenced.contains(name),
                  !protected.contains(name) else { continue }
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
            lastPrunedProtected = protected
        }
    }
}
