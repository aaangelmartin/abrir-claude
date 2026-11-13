// renders the app icon: claude's mark in white on claude's clay orange, as a macOS iconset.
// usage: swift scripts/make-icon.swift <claude.svg> <out.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let mark = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: make-icon.swift <svg> <out.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let tileColor = NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
let markColor = NSColor.white

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // apple's grid: the tile is 824 of 1024, centred, radius ~185
    let tile = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    tileColor.setFill()
    path.fill()
    NSColor.white.withAlphaComponent(0.10).setStroke()
    path.lineWidth = max(1, s / 512)
    path.stroke()

    // the mark, tinted
    let side = tile.width * 0.52
    let markRect = NSRect(x: tile.midX - side / 2, y: tile.midY - side / 2, width: side, height: side)
    let tinted = NSImage(size: markRect.size, flipped: false) { r in
        mark.draw(in: r)
        markColor.set()
        r.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: markRect)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
