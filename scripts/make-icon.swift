// Renders packaging/AppIcon.icns: an orange "C" on a black squircle.
// Run: swift scripts/make-icon.swift   (then commit the regenerated icns)
import AppKit
import CoreGraphics
import Foundation

let repoRoot = FileManager.default.currentDirectoryPath
let iconsetPath = NSTemporaryDirectory() + "AppIcon.iconset"
let icnsPath = repoRoot + "/packaging/AppIcon.icns"

// Colors from ClaudetteUI's Theme: calm #F26A46 over the island's black.
let orangeTop = NSColor(srgbRed: 0xF5 / 255.0, green: 0x7A / 255.0, blue: 0x52 / 255.0, alpha: 1)
let orangeBottom = NSColor(srgbRed: 0xEF / 255.0, green: 0x5C / 255.0, blue: 0x3A / 255.0, alpha: 1)
let surfaceTop = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
let surfaceBottom = NSColor(srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1)

func render(pixels: Int) -> CGImage {
    let s = CGFloat(pixels)
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc

    // Apple's icon grid: the squircle spans 824/1024 of the canvas.
    let inset = s * 100 / 1024
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 185.4 / 824
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGradient(starting: surfaceTop, ending: surfaceBottom)!.draw(in: squircle, angle: -90)

    // Hairline highlight along the top edge, like the island's border.
    squircle.lineWidth = max(1, s / 512)
    NSColor.white.withAlphaComponent(0.09).setStroke()
    squircle.stroke()

    // The C: retro pixel glyph, 2-cell strokes with cut corners.
    let grid = [
        ".xxxx.",
        "xx..xx",
        "xx....",
        "xx....",
        "xx....",
        "xx..xx",
        ".xxxx.",
    ]
    let rows = grid.count
    let cols = grid[0].count
    let glyphHeight = rect.height * 0.59
    let cell = glyphHeight / CGFloat(rows)
    let glyphWidth = cell * CGFloat(cols)
    let originX = rect.midX - glyphWidth / 2
    let originY = rect.midY - glyphHeight / 2
    let pixelInset = cell * 0.05

    let glyphPath = CGMutablePath()
    for (r, row) in grid.enumerated() {
        for (c, ch) in row.enumerated() where ch == "x" {
            glyphPath.addRect(CGRect(
                x: originX + CGFloat(c) * cell + pixelInset,
                y: originY + CGFloat(rows - 1 - r) * cell + pixelInset,
                width: cell - 2 * pixelInset,
                height: cell - 2 * pixelInset))
        }
    }

    ctx.saveGState()
    ctx.addPath(glyphPath)
    ctx.clip()
    let colors = [orangeTop.cgColor, orangeBottom.cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: ctx.colorSpace, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: [])
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    writePNG(render(pixels: base), to: "\(iconsetPath)/icon_\(base)x\(base).png")
    writePNG(render(pixels: base * 2), to: "\(iconsetPath)/icon_\(base)x\(base)@2x.png")
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(icnsPath)")
