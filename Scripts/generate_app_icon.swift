import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? ".build/CarelessWhisper.icns"
let outputURL = URL(fileURLWithPath: outputPath)
let buildDir = outputURL.deletingLastPathComponent()
let iconsetURL = buildDir.appendingPathComponent("CarelessWhisper.iconset", isDirectory: true)

try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

func scaled(_ value: CGFloat, _ size: CGFloat) -> CGFloat {
    value / 1024.0 * size
}

func renderIcon(size: Int) throws -> Data {
    let side = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "CarelessWhisperIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let bounds = NSRect(x: 0, y: 0, width: side, height: side)
    NSColor.clear.setFill()
    bounds.fill()

    let background = NSBezierPath(
        roundedRect: bounds.insetBy(dx: scaled(72, side), dy: scaled(72, side)),
        xRadius: scaled(220, side),
        yRadius: scaled(220, side)
    )
    NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.11, alpha: 1.0),
        NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.19, alpha: 1.0)
    ])?.draw(in: background, angle: -42)

    NSColor(calibratedRed: 0.16, green: 0.77, blue: 0.95, alpha: 1.0).setFill()
    NSBezierPath(
        ovalIn: NSRect(
            x: scaled(724, side),
            y: scaled(168, side),
            width: scaled(116, side),
            height: scaled(116, side)
        )
    ).fill()

    let shadow = NSShadow()
    shadow.shadowBlurRadius = scaled(26, side)
    shadow.shadowOffset = NSSize(width: 0, height: -scaled(10, side))
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.set()

    let waveform = NSBezierPath()
    waveform.lineCapStyle = .round
    waveform.lineJoinStyle = .round
    waveform.lineWidth = scaled(86, side)

    let points: [NSPoint] = [
        NSPoint(x: scaled(164, side), y: scaled(512, side)),
        NSPoint(x: scaled(268, side), y: scaled(338, side)),
        NSPoint(x: scaled(382, side), y: scaled(686, side)),
        NSPoint(x: scaled(512, side), y: scaled(230, side)),
        NSPoint(x: scaled(642, side), y: scaled(794, side)),
        NSPoint(x: scaled(756, side), y: scaled(338, side)),
        NSPoint(x: scaled(860, side), y: scaled(512, side))
    ]

    NSColor.white.setStroke()
    waveform.move(to: points[0])
    for point in points.dropFirst() {
        waveform.line(to: point)
    }
    waveform.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CarelessWhisperIcon", code: 2)
    }
    return data
}

for variant in variants {
    let pixels = variant.points * variant.scale
    let suffix = variant.scale == 1 ? "" : "@\(variant.scale)x"
    let filename = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    let data = try renderIcon(size: pixels)
    try data.write(to: iconsetURL.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "CarelessWhisperIcon", code: Int(process.terminationStatus))
}
