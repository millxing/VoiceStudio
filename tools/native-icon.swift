import AppKit
import Foundation
let folder = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSColor.systemIndigo.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: Double(pixels) * 0.06, dy: Double(pixels) * 0.06), xRadius: Double(pixels) * 0.22, yRadius: Double(pixels) * 0.22).fill()
        if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: Double(pixels) * 0.48, weight: .medium)) {
            let s = symbol.size
            let rect = NSRect(x: (Double(pixels) - s.width) / 2, y: (Double(pixels) - s.height) / 2, width: s.width, height: s.height)
            let tinted = NSImage(size: s)
            tinted.lockFocus(); NSColor.white.set(); NSRect(origin: .zero, size: s).fill(); symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1); tinted.unlockFocus()
            tinted.draw(in: rect)
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
