import Foundation

/// `state.json` の保存・読込・デバウンス・破損処理（SPEC §10）。
final class StateStore {
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
    private var pendingSave: DispatchWorkItem?
    /// 未保存の変更のうち、いちばん古いものが積まれた時刻
    private var oldestPendingChange: Date?
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
         fileManager: FileManager = .default) {
        self.directory = directory
        self.debounceInterval = debounceInterval
        self.maxSaveDelay = maxSaveDelay
        self.fileManager = fileManager
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
        guard fileManager.fileExists(atPath: stateFileURL.path) else { return .empty }

        do {
            let data = try Data(contentsOf: stateFileURL)
            let state = try JSONDecoder().decode(AppState.self, from: data)
            guard state.version == AppState.currentVersion else {
                // 未知のバージョンは解釈できない。上書きせず退避する。
                allowsImagePruning = false
                return .recovered(backupURL: try quarantineStateFile(reason: "version-\(state.version)"))
            }
            return .loaded(state)
        } catch {
            NSLog("[Ttemp] state.json を読めなかった: \(error.localizedDescription)")
            allowsImagePruning = false
            if let backup = try? quarantineStateFile(reason: "corrupt") {
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
        let delay: TimeInterval
        if let oldest = oldestPendingChange {
            // 最初の未保存の変更からの経過時間で頭打ちにする
            let remaining = maxSaveDelay - Date().timeIntervalSince(oldest)
            delay = max(0, min(debounceInterval, remaining))
        } else {
            oldestPendingChange = Date()
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
        performSave()
    }

    private func performSave() {
        pendingSave = nil
        oldestPendingChange = nil
        guard let state = snapshotProvider?() else { return }
        do {
            try save(state)
        } catch {
            NSLog("[Ttemp] state.json の保存に失敗した: \(error.localizedDescription)")
        }
    }

    func save(_ state: AppState) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        // SPEC §10.4: アトミック書き込み（一時ファイルに書いてから rename）
        try data.write(to: stateFileURL, options: .atomic)
        // state.json を書いた後にだけ孤児画像を掃除する（順序を逆にすると
        // 保存に失敗した場合に参照されている画像を消してしまう）
        pruneUnreferencedImages(keeping: state)
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
        lastPrunedReferences = referenced
        guard let entries = try? fileManager.contentsOfDirectory(at: imagesDirectoryURL,
                                                                includingPropertiesForKeys: nil) else { return }
        for entry in entries where !referenced.contains(entry.lastPathComponent) {
            try? fileManager.removeItem(at: entry)
        }
    }
}
