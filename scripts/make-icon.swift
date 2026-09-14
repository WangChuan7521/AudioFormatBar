import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("usage: make-icon.swift <source-image> <output-iconset>\n", stderr)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL),
      let sourceCGImage = sourceImage.cgImage(
        forProposedRect: nil,
        context: nil,
        hints: nil
      ) else {
    fputs("unable to load source image\n", stderr)
    exit(1)
}

let sourceWidth = sourceCGImage.width
let sourceHeight = sourceCGImage.height
let cropSide = min(sourceWidth, sourceHeight)
let cropRect = CGRect(
    x: (sourceWidth - cropSide) / 2,
    y: (sourceHeight - cropSide) / 2,
    width: cropSide,
    height: cropSide
)

guard let squareImage = sourceCGImage.cropping(to: cropRect) else {
    fputs("unable to crop source image\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true
)

let variants: [(name: String, pixels: Int)] = [
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

for variant in variants {
    let pixels = variant.pixels
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("unable to create bitmap for \(variant.name)\n", stderr)
        exit(1)
    }

    let size = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.205

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    NSColor.clear.setFill()
    rect.fill()
    NSBezierPath(
        roundedRect: rect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    ).addClip()

    NSImage(cgImage: squareImage, size: NSSize(width: size, height: size))
        .draw(
            in: rect,
            from: .zero,
            operation: .copy,
            fraction: 1
        )

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fputs("unable to encode \(variant.name)\n", stderr)
        exit(1)
    }

    try data.write(to: iconsetURL.appendingPathComponent(variant.name))
}
