#!/usr/bin/env swift

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = outputURL
    .deletingPathExtension()
    .appendingPathExtension("iconset")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let icons: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in icons {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(filename)")
    }

    try png.write(to: iconsetURL.appendingPathComponent(filename))
}

try? FileManager.default.removeItem(at: outputURL)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconsetURL.path,
    "-o",
    outputURL.path
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}

try? FileManager.default.removeItem(at: iconsetURL)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer {
        image.unlockFocus()
    }

    let scale = size / 1024.0
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
    }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let base = NSBezierPath(
        roundedRect: rect(72, 72, 880, 880),
        xRadius: 210 * scale,
        yRadius: 210 * scale
    )
    NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.11, alpha: 1).setFill()
    base.fill()

    let inner = NSBezierPath(
        roundedRect: rect(116, 116, 792, 792),
        xRadius: 170 * scale,
        yRadius: 170 * scale
    )
    NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.17, alpha: 1).setFill()
    inner.fill()

    drawCloud(scale: scale)
    drawCheck(scale: scale)
    drawBadge(scale: scale)

    return image
}

func drawCloud(scale: CGFloat) {
    let cloud = NSBezierPath()
    cloud.move(to: NSPoint(x: 300 * scale, y: 430 * scale))
    cloud.curve(
        to: NSPoint(x: 402 * scale, y: 546 * scale),
        controlPoint1: NSPoint(x: 296 * scale, y: 496 * scale),
        controlPoint2: NSPoint(x: 333 * scale, y: 540 * scale)
    )
    cloud.curve(
        to: NSPoint(x: 538 * scale, y: 650 * scale),
        controlPoint1: NSPoint(x: 424 * scale, y: 625 * scale),
        controlPoint2: NSPoint(x: 482 * scale, y: 666 * scale)
    )
    cloud.curve(
        to: NSPoint(x: 674 * scale, y: 552 * scale),
        controlPoint1: NSPoint(x: 610 * scale, y: 690 * scale),
        controlPoint2: NSPoint(x: 676 * scale, y: 632 * scale)
    )
    cloud.curve(
        to: NSPoint(x: 744 * scale, y: 408 * scale),
        controlPoint1: NSPoint(x: 737 * scale, y: 542 * scale),
        controlPoint2: NSPoint(x: 784 * scale, y: 484 * scale)
    )
    cloud.curve(
        to: NSPoint(x: 626 * scale, y: 320 * scale),
        controlPoint1: NSPoint(x: 712 * scale, y: 346 * scale),
        controlPoint2: NSPoint(x: 672 * scale, y: 320 * scale)
    )
    cloud.line(to: NSPoint(x: 334 * scale, y: 320 * scale))
    cloud.curve(
        to: NSPoint(x: 300 * scale, y: 430 * scale),
        controlPoint1: NSPoint(x: 276 * scale, y: 320 * scale),
        controlPoint2: NSPoint(x: 246 * scale, y: 382 * scale)
    )
    cloud.close()

    NSColor(calibratedRed: 0.95, green: 0.99, blue: 1.0, alpha: 1).setFill()
    cloud.fill()

    let ring = NSBezierPath()
    ring.appendOval(in: NSRect(x: 280 * scale, y: 330 * scale, width: 300 * scale, height: 300 * scale))
    ring.appendOval(in: NSRect(x: 444 * scale, y: 326 * scale, width: 294 * scale, height: 294 * scale))
    ring.lineWidth = 48 * scale
    NSColor(calibratedRed: 0.06, green: 0.46, blue: 0.95, alpha: 1).setStroke()
    ring.stroke()

    let lowerLoop = NSBezierPath()
    lowerLoop.appendOval(in: NSRect(x: 350 * scale, y: 252 * scale, width: 328 * scale, height: 328 * scale))
    lowerLoop.lineWidth = 48 * scale
    NSColor(calibratedRed: 0.07, green: 0.78, blue: 0.52, alpha: 1).setStroke()
    lowerLoop.stroke()
}

func drawCheck(scale: CGFloat) {
    let check = NSBezierPath()
    check.move(to: NSPoint(x: 390 * scale, y: 430 * scale))
    check.line(to: NSPoint(x: 474 * scale, y: 350 * scale))
    check.line(to: NSPoint(x: 646 * scale, y: 546 * scale))
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.lineWidth = 54 * scale
    NSColor.white.setStroke()
    check.stroke()
}

func drawBadge(scale: CGFloat) {
    NSColor(calibratedRed: 1.0, green: 0.23, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 690 * scale, y: 676 * scale, width: 138 * scale, height: 138 * scale)).fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 78 * scale, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    NSString(string: "1").draw(
        in: NSRect(x: 690 * scale, y: 702 * scale, width: 138 * scale, height: 88 * scale),
        withAttributes: attributes
    )
}
