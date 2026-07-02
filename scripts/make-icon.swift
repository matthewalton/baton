// Renders the Baton app icon into an .iconset directory.
// Usage: swift scripts/make-icon.swift <output.iconset>
// Design: burnt-orange squircle with a relay baton mid-handoff — a hollow
// white tube at 45° with speed streaks trailing behind it.
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
    ctx.setFillColor(srgb(0xE05A1A))
    ctx.fillPath()
    ctx.restoreGState()

    // Vertical burnt-orange gradient.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colors = [srgb(0xF98A3C), srgb(0xE05A1A)] as CFArray
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

    // Relay baton mid-handoff: axes rotated 45° so +x runs along the baton,
    // pointing up-right. Drawn as an open cylinder — the elliptical mouth at
    // the leading end is what makes it read as a tube.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512)
    ctx.rotate(by: .pi / 4)

    let tubeWidth: CGFloat = 148          // baton diameter
    let tubeBack: CGFloat = -220          // trailing end along the axis
    let tubeFront: CGFloat = 280          // leading end (mouth) along the axis
    let endDepth: CGFloat = tubeWidth * 0.30  // ellipse semi-axis giving the cylinder its 3D tilt

    // Speed streaks trailing the baton, slightly translucent.
    ctx.setFillColor(srgb(0xFFFFFF, 0.65))
    for streak in [CGRect(x: -430, y: -76, width: 150, height: 44),
                   CGRect(x: -470, y: 32, width: 190, height: 44)] {
        ctx.addPath(CGPath(roundedRect: streak, cornerWidth: 22, cornerHeight: 22, transform: nil))
    }
    ctx.fillPath()

    // Tube body: rectangle with a rounded trailing end and an elliptical bulge
    // at the leading end (the far rim of the mouth).
    let body = CGMutablePath()
    body.addRoundedRect(
        in: CGRect(x: tubeBack, y: -tubeWidth / 2, width: tubeFront - tubeBack, height: tubeWidth),
        cornerWidth: 30,
        cornerHeight: 30
    )
    body.addEllipse(in: CGRect(x: tubeFront - endDepth, y: -tubeWidth / 2, width: endDepth * 2, height: tubeWidth))
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: srgb(0x000000, 0.22))
    ctx.addPath(body)
    ctx.setFillColor(srgb(0xFFFFFF, 0.95))
    ctx.fillPath()

    // Mouth of the tube: a darker inset ellipse reads as the hollow inside.
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let mouthDepth = endDepth * 0.62
    let mouthRadius = tubeWidth / 2 * 0.62
    ctx.addEllipse(in: CGRect(x: tubeFront - mouthDepth, y: -mouthRadius, width: mouthDepth * 2, height: mouthRadius * 2))
    ctx.setFillColor(srgb(0xC24E12))
    ctx.fillPath()
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
