import AppKit

let diagnostics: RuntimeDiagnostics?
do {
    diagnostics = try RuntimeDiagnostics.fromArguments()
} catch {
    fputs("Ttemp diagnostics: \(error)\n", stderr)
    exit(1)
}
// Reject unsafe diagnostics before creating NSApplication or any status item.
let application = NSApplication.shared
let appDelegate = AppDelegate(diagnostics: diagnostics)
application.delegate = appDelegate
application.run()
