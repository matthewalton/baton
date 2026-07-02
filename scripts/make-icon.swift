// Renders the Baton app icon into an .iconset directory.
// Usage: swift scripts/make-icon.swift <output.iconset>
// Design: iris-indigo squircle with a diagonal relay-baton glyph.
import AppKit
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}
let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Draws the icon in a 1024×1024 coordinate space (origin bottom-left).
func draw(in ctx: CGContext) {
    let squircle = CGPath(
        roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
        cornerWidth: 186,
        cornerHeight: 186,
        transform: nil
    )

    // Soft drop shadow behind the tile, per macOS icon convention.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: srgb(0x000000, 0.30))
    ctx.addPath(squircle)
    ctx.setFillColor(srgb(0x4952BE))
    ctx.fillPath()
    ctx.restoreGState()

    // Vertical iris gradient.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colors = [srgb(0x6875E4), srgb(0x4952BE)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 512, y: 924),
        end: CGPoint(x: 512, y: 100),
        options: []
    )
    // Faint top sheen.
    let sheen = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [srgb(0xFFFFFF, 0.10), srgb(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: 512, y: 924),
        end: CGPoint(x: 512, y: 560),
        options: []
    )
    ctx.restoreGState()

    // Relay baton: a white capsule at 45° with two indigo grip bands.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512)
    ctx.rotate(by: .pi / 4)

    let batonLength: CGFloat = 620
    let batonWidth: CGFloat = 168
    let capsule = CGPath(
        roundedRect: CGRect(x: -batonLength / 2, y: -batonWidth / 2, width: batonLength, height: batonWidth),
        cornerWidth: batonWidth / 2,
        cornerHeight: batonWidth / 2,
        transform: nil
    )
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: srgb(0x000000, 0.22))
    ctx.addPath(capsule)
    ctx.setFillColor(srgb(0xFFFFFF, 0.95))
    ctx.fillPath()

    // Grip bands, clipped to the capsule so their ends follow its curve.
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(capsule)
    ctx.clip()
    ctx.setFillColor(srgb(0x4952BE))
    for centerX: CGFloat in [-168, 168] {
        ctx.fill(CGRect(x: centerX - 27, y: -batonWidth / 2, width: 54, height: batonWidth))
    }
    ctx.restoreGState()
}

func writePNG(points: Int, scale: Int) throws {
    let pixels = points * scale
    let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(in: ctx)

    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    let url = outputDir.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

for points in [16, 32, 128, 256, 512] {
    try writePNG(points: points, scale: 1)
    try writePNG(points: points, scale: 2)
}
print("Wrote iconset to \(outputDir.path)")
