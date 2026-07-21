import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
let shouldDrawDevelopmentBadge = arguments.contains("--dev-badge")
let positionalArguments = arguments.dropFirst().filter { $0 != "--dev-badge" }
guard (1...2).contains(positionalArguments.count) else {
    fputs("用法：swift generate_app_icon.swift <输出 iconset 目录> [源 PNG] [--dev-badge]\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: positionalArguments[0], isDirectory: true)
let sourceURL = URL(fileURLWithPath: positionalArguments.count == 2
    ? positionalArguments[1]
    : "Resources/BrandIcons/NoboardIconBlue.png")
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let outputs: [(name: String, pixels: Int)] = [
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

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("无法读取源图标：\(sourceURL.path)\n", stderr)
    exit(1)
}

func renderIcon(size: Int) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "AkangVoiceInputIcon", code: 1)
    }

    context.interpolationQuality = .high
    context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    if shouldDrawDevelopmentBadge {
        drawDevelopmentBadge(in: context, size: size)
    }

    guard let image = context.makeImage() else {
        throw NSError(domain: "AkangVoiceInputIcon", code: 2)
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "AkangVoiceInputIcon", code: 3)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "AkangVoiceInputIcon", code: 4)
    }
    return data as Data
}

func drawDevelopmentBadge(in context: CGContext, size: Int) {
    let badgeSize = CGFloat(size) * 0.42
    let margin = CGFloat(size) * 0.05
    let rect = CGRect(
        x: CGFloat(size) - badgeSize - margin,
        y: CGFloat(size) - badgeSize - margin,
        width: badgeSize,
        height: badgeSize
    )
    let radius = badgeSize * 0.25
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: max(1, badgeSize * -0.04)),
        blur: max(1, badgeSize * 0.12),
        color: CGColor(red: 0.02, green: 0.05, blue: 0.18, alpha: 0.35)
    )
    context.setFillColor(CGColor(red: 1.0, green: 0.32, blue: 0.06, alpha: 1.0))
    context.addPath(path)
    context.fillPath()
    context.restoreGState()

    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.92))
    context.setLineWidth(max(1, badgeSize * 0.055))
    context.addPath(path)
    context.strokePath()

    let label = "D" as CFString
    let fontSize = badgeSize * 0.68
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: CTFontCreateWithName("HelveticaNeue-CondensedBlack" as CFString, fontSize, nil),
        kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    ]
    let attributedLabel = CFAttributedStringCreate(nil, label, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributedLabel)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

    context.textMatrix = .identity
    context.textPosition = CGPoint(
        x: rect.midX - bounds.width / 2 - bounds.minX,
        y: rect.midY - bounds.height / 2 - bounds.minY
    )
    CTLineDraw(line, context)
}

for output in outputs {
    let data = try renderIcon(size: output.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(output.name), options: .atomic)
}
