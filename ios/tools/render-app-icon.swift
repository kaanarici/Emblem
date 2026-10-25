import AppKit
let args = CommandLine.arguments
let size = args.count > 3 ? Int(args[3])! : 240
let icon = NSWorkspace.shared.icon(forFile: args[1])
let big = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: big, pixelsHigh: big, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
icon.draw(in: NSRect(x: 0, y: 0, width: big, height: big), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
var minX = big, minY = big, maxX = 0, maxY = 0
for y in 0..<big { for x in 0..<big where rep.colorAt(x: x, y: y)!.alphaComponent > 0.05 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
let side = max(maxX - minX, maxY - minY) + 1
let crop = rep.cgImage!.cropping(to: CGRect(x: minX, y: minY, width: side, height: side))!
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: out)!
ctx.imageInterpolation = .high
NSGraphicsContext.current = ctx
NSImage(cgImage: crop, size: NSSize(width: side, height: side)).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print(args[2], "bounds", minX, minY, side)
