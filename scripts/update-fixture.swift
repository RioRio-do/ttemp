// Local-only Sparkle integration fixtures. Never use distribution keys.
import Foundation
import CryptoKit

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: update-fixture.swift prepare|sign|cleanup DIRECTORY [APP URL]") }
let root = URL(fileURLWithPath: args[2], isDirectory: true)
let fm = FileManager.default
let metadata = root.appendingPathComponent("fixture.plist")

func readInfo(_ url: URL) throws -> [String: Any] {
    try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: Any]
}
func writeInfo(_ info: [String: Any], to url: URL) throws {
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url)
}

do {
    switch args[1] {
    case "prepare":
        guard args.count == 5 else { fatalError("prepare requires APP URL") }
        let key = Curve25519.Signing.PrivateKey()
        let identifier = "com.am921.ttemp.update-test.\(UUID().uuidString)"
        try writeInfo(["id": identifier, "url": args[4]], to: metadata)
        try key.rawRepresentation.write(to: root.appendingPathComponent("key"), options: .atomic)
        for (folder, version) in [("old", "1"), ("new", "2")] {
            let directory = root.appendingPathComponent(folder)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let app = directory.appendingPathComponent("Ttemp.app")
            try fm.copyItem(at: URL(fileURLWithPath: args[3]), to: app)
            let infoURL = app.appendingPathComponent("Contents/Info.plist")
            var info = try readInfo(infoURL)
            info["CFBundleIdentifier"] = identifier
            info["CFBundleVersion"] = version
            info["CFBundleShortVersionString"] = "0.0.\(version)"
            info["SUPublicEDKey"] = key.publicKey.rawRepresentation.base64EncodedString()
            info["SUFeedURL"] = args[4] + "/appcast.xml"
            info["NSAppTransportSecurity"] = ["NSAllowsLocalNetworking": true]
            try writeInfo(info, to: infoURL)
        }
    case "sign":
        let info = try readInfo(metadata)
        let url = info["url"] as! String
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: root.appendingPathComponent("key")))
        let archive = try Data(contentsOf: root.appendingPathComponent("feed/Ttemp.zip"))
        let signature = try key.signature(for: archive).base64EncodedString()
        let payload = Data("""
        <?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Ttemp Test</title><item>
        <enclosure url="\(url)/Ttemp.zip" sparkle:version="2" sparkle:shortVersionString="0.0.2" sparkle:edSignature="\(signature)" length="\(archive.count)" type="application/octet-stream"/>
        </item></channel></rss>
        """.utf8)
        let feed = payload + Data("<!-- sparkle-signatures:\nedSignature: \(try key.signature(for: payload).base64EncodedString())\nlength: \(payload.count)\n-->\n".utf8)
        try feed.write(to: root.appendingPathComponent("feed/appcast.xml"))
        var corrupted = feed
        corrupted[0] ^= 1
        try corrupted.write(to: root.appendingPathComponent("feed/bad-appcast.xml"))
    case "tamper-archive":
        let archiveURL = root.appendingPathComponent("feed/Ttemp.zip")
        var data = try Data(contentsOf: archiveURL)
        guard data.count > 32 else { fatalError("Missing test archive") }
        data[32] ^= 1
        try data.write(to: archiveURL)
    case "cleanup":
        guard fm.fileExists(atPath: metadata.path) else { break }
        let info = try readInfo(metadata)
        guard let identifier = info["id"] as? String,
              identifier.hasPrefix("com.am921.ttemp.update-test."),
              UUID(uuidString: String(identifier.dropFirst("com.am921.ttemp.update-test.".count))) != nil else {
            fatalError("Invalid fixture ID")
        }
        UserDefaults.standard.removePersistentDomain(forName: identifier)
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fm.removeItem(at: caches.appendingPathComponent(identifier))
        }
    default:
        fatalError("Unknown fixture operation")
    }
} catch {
    fputs("Update fixture failed: \(error)\n", stderr)
    exit(1)
}
