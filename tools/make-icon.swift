// Renders assets/icon.png onto a square 1024px canvas (with macOS-style margin) and writes an .icns.
// Usage: swift tools/make-icon.swift <source.png> <output.icns>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: make-icon.swift <source.png> <output.icns>\n".data(using: .utf8)!)
    exit(1)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let box = CGFloat(px) * 0.8, inset = (CGFloat(px) - box) / 2
    let s = src.size, k = min(box / s.width, box / s.height)
    let r = NSRect(x: inset + (box - s.width * k) / 2, y: inset + (box - s.height * k) / 2, width: s.width * k, height: s.height * k)
    src.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", args[2]]
try! p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
exit(p.terminationStatus)
