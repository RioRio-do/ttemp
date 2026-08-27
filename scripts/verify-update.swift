import Foundation
import CryptoKit

struct VerificationError: Error, CustomStringConvertible {
    let description: String
}

func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw VerificationError(description: message) }
}

/// Verify with the public key actually shipped in the app, not the signing tool's
/// private key. This catches signing with the wrong (but internally consistent) key.
func verify(info: [String: Any], archive: Data, feed: Data) throws {
    guard let keyString = info["SUPublicEDKey"] as? String, let keyData = Data(base64Encoded: keyString),
          let version = info["CFBundleShortVersionString"] as? String,
          let build = info["CFBundleVersion"] as? String else {
        throw VerificationError(description: "Missing app update metadata")
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    try require(info["SURequireSignedFeed"] as? Bool == true, "Signed feed must be required")
    try require(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true, "Archive must be verified before extraction")
    let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    guard let range = feed.range(of: prefix, options: .backwards),
          let block = String(data: feed[range.upperBound...], encoding: .utf8) else {
        throw VerificationError(description: "Missing signed appcast block")
    }
    let payload = Data(feed[..<range.lowerBound])
    let fields = block.components(separatedBy: "\n")
    guard fields.count == 4, fields[2] == "-->", fields[3].isEmpty,
          fields[0].hasPrefix("edSignature: "), fields[1].hasPrefix("length: "),
          let signature = Data(base64Encoded: String(fields[0].dropFirst("edSignature: ".count))),
          let length = Int(fields[1].dropFirst("length: ".count)) else {
        throw VerificationError(description: "Malformed signed appcast block")
    }
    try require(length == payload.count, "Appcast signed length mismatch")
    try require(key.isValidSignature(signature, for: payload), "Appcast does not match the shipped public key")
    let xml = try XMLDocument(data: payload, options: [.nodeLoadExternalEntitiesNever])
    let items = try xml.nodes(forXPath: "/rss/channel/item/enclosure")
    guard items.count == 1, let enclosure = items.first as? XMLElement,
          let archiveSignatureText = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
          let archiveSignature = Data(base64Encoded: archiveSignatureText) else {
        throw VerificationError(description: "Expected one signed update enclosure")
    }
    try require(enclosure.attribute(forName: "sparkle:version")?.stringValue == build, "Build number mismatch")
    try require(enclosure.attribute(forName: "sparkle:shortVersionString")?.stringValue == version, "Version mismatch")
    try require(enclosure.attribute(forName: "length")?.stringValue == String(archive.count), "ZIP length mismatch")
    try require(enclosure.attribute(forName: "url")?.stringValue ==
                "https://github.com/RioRio-do/ttemp/releases/download/v\(version)/Ttemp.zip", "Unexpected update URL")
    try require(key.isValidSignature(archiveSignature, for: archive), "ZIP does not match the shipped public key")
}

func selfTest() throws {
    let key = Curve25519.Signing.PrivateKey()
    let archive = Data("test archive".utf8)
    let info: [String: Any] = ["SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString(),
                              "CFBundleShortVersionString": "0.1.99", "CFBundleVersion": "99",
                              "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true]
    let archiveSignature = try key.signature(for: archive).base64EncodedString()
    let xml = """
    <?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
    <enclosure url="https://github.com/RioRio-do/ttemp/releases/download/v0.1.99/Ttemp.zip" sparkle:version="99" sparkle:shortVersionString="0.1.99" sparkle:edSignature="\(archiveSignature)" length="\(archive.count)"/>
    </item></channel></rss>
    """
    let payload = Data(xml.utf8)
    let feed = payload + Data("<!-- sparkle-signatures:\nedSignature: \(try key.signature(for: payload).base64EncodedString())\nlength: \(payload.count)\n-->\n".utf8)
    try verify(info: info, archive: archive, feed: feed)
    func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch { return }
        throw VerificationError(description: "Negative signature test was accepted")
    }
    try rejects { try verify(info: info, archive: archive + Data([0]), feed: feed) }
    var wrongInfo = info
    wrongInfo["SUPublicEDKey"] = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
    try rejects { try verify(info: wrongInfo, archive: archive, feed: feed) }
    wrongInfo = info
    wrongInfo["CFBundleVersion"] = "100"
    try rejects { try verify(info: wrongInfo, archive: archive, feed: feed) }
    var changedFeed = feed
    changedFeed[0] ^= 1
    try rejects { try verify(info: info, archive: archive, feed: changedFeed) }
    print("UPDATE_VERIFIER_TEST_OK 5 checks")
}

do {
    if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
        try selfTest()
    } else {
        let args = CommandLine.arguments
        try require(args.count == 4, "usage: verify-update.swift Ttemp.app Ttemp.zip appcast.xml")
        let infoURL = URL(fileURLWithPath: args[1]).appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw VerificationError(description: "Invalid app Info.plist")
        }
        try verify(info: info, archive: Data(contentsOf: URL(fileURLWithPath: args[2])),
                   feed: Data(contentsOf: URL(fileURLWithPath: args[3])))
        print("UPDATE_SIGNATURES_OK (shipped public key, versions, lengths, URL)")
    }
} catch {
    fputs("Update verification failed: \(error)\n", stderr)
    exit(1)
}
