import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("用法：swift generate_app_icon.swift <输出 iconset 目录>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
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

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = CGFloat(size) * 0.055
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(size) * 0.22

    let background = CGPath(
        roundedRect: iconRect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
    context.addPath(background)
    context.setFillColor(CGColor(red: 0.035, green: 0.36, blue: 0.23, alpha: 1))
    context.fillPath()

    context.saveGState()
    context.addPath(background)
    context.clip()
    context.setFillColor(CGColor(red: 0.08, green: 0.48, blue: 0.31, alpha: 0.72))
    context.fill(CGRect(x: iconRect.minX, y: iconRect.midY, width: iconRect.width, height: iconRect.height / 2))
    context.restoreGState()

    let relativeHeights: [CGFloat] = [0.30, 0.55, 0.82, 0.50, 1.0, 0.50, 0.82, 0.55, 0.30]
    let barWidth = CGFloat(size) * 0.055
    let gap = CGFloat(size) * 0.035
    let totalWidth = CGFloat(relativeHeights.count) * barWidth + CGFloat(relativeHeights.count - 1) * gap
    let maxHeight = CGFloat(size) * 0.43
    let startX = rect.midX - totalWidth / 2
    context.setFillColor(CGColor(gray: 1, alpha: 1))

    for (index, relativeHeight) in relativeHeights.enumerated() {
        let height = max(barWidth, maxHeight * relativeHeight)
        let barRect = CGRect(
            x: startX + CGFloat(index) * (barWidth + gap),
            y: rect.midY - height / 2,
            width: barWidth,
            height: height
        )
        context.addPath(CGPath(
            roundedRect: barRect,
            cornerWidth: barWidth / 2,
            cornerHeight: barWidth / 2,
            transform: nil
        ))
        context.fillPath()
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

for output in outputs {
    let data = try renderIcon(size: output.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(output.name), options: .atomic)
}
