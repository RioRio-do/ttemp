import AppKit

let application = NSApplication.shared
let diagnostics: RuntimeDiagnostics?
do {
    diagnostics = try RuntimeDiagnostics.fromArguments()
} catch {
    fputs("Ttemp diagnostics: \(error)\n", stderr)
    exit(1)
}
let appDelegate = AppDelegate(diagnostics: diagnostics)
application.delegate = appDelegate
application.run()
