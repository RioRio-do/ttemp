import Foundation

/// Originals written by background imports are not orphans until the main thread
/// has installed them *and* a snapshot taken after installation has reached disk.
final class PendingImageImports {
    private let lock = NSLock()
    private var fileNames: Set<String> = []
    private var installed: Set<String> = []

    func protect(_ reference: ImageReference) {
        lock.lock()
        defer { lock.unlock() }
        fileNames.insert(reference.fileName)
    }

    func release(_ reference: ImageReference) {
        lock.lock()
        defer { lock.unlock() }
        fileNames.remove(reference.fileName)
        installed.remove(reference.fileName)
    }

    /// Called on the main thread only after the window owns the imported image.
    func didInstall(_ reference: ImageReference) {
        lock.lock()
        defer { lock.unlock() }
        if fileNames.contains(reference.fileName) { installed.insert(reference.fileName) }
    }

    /// Capture alongside a state snapshot, before enqueuing its disk write. A
    /// later successful save may release these even if the image was already
    /// closed/replaced before the first save. Older queued saves may not.
    func installedBeforeSnapshot() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return installed
    }

    /// Hold the lock during pruning so a write cannot register between a stale
    /// protection snapshot and deletion. Import writes happen only after protect().
    func whilePruning(releasing completed: Set<String>, _ action: (Set<String>) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        fileNames.subtract(completed)
        installed.subtract(completed)
        action(fileNames)
    }
}
