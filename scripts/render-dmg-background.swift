#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-dmg-background.swift OUTPUT.png\n".utf8))
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvasSize = NSSize(width: 660, height: 400)
let image = NSImage(size: canvasSize)

image.lockFocus()

let bounds = NSRect(origin: .zero, size: canvasSize)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.965, green: 0.973, blue: 0.988, alpha: 1),
    ending: NSColor(calibratedRed: 0.900, green: 0.929, blue: 0.976, alpha: 1)
)
gradient?.draw(in: bounds, angle: -90)

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
    .paragraphStyle: titleStyle,
]
"Ttemp".draw(
    in: NSRect(x: 0, y: 320, width: canvasSize.width, height: 44),
    withAttributes: titleAttributes
)

let arrowColor = NSColor(calibratedRed: 0.24, green: 0.43, blue: 0.74, alpha: 0.82)
arrowColor.setStroke()
arrowColor.setFill()

let shaft = NSBezierPath()
shaft.lineWidth = 5
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 268, y: 195))
shaft.line(to: NSPoint(x: 392, y: 195))
shaft.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 392, y: 210))
arrowHead.line(to: NSPoint(x: 418, y: 195))
arrowHead.line(to: NSPoint(x: 392, y: 180))
arrowHead.close()
arrowHead.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render DMG background\n".utf8))
    exit(1)
}

do {
    try png.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("failed to write DMG background: \(error)\n".utf8))
    exit(1)
}
