#!/usr/bin/env swift

import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("用法：generate_dmg_background.swift <输出 PNG> <版本号>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let version = CommandLine.arguments[2]
let canvasSize = NSSize(width: 660, height: 420)
let image = NSImage(size: canvasSize)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawCenteredText(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let size = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: (canvasSize.width - size.width) / 2, y: y),
        withAttributes: attributes
    )
}

image.lockFocus()

let backgroundRect = NSRect(origin: .zero, size: canvasSize)
let backgroundGradient = NSGradient(
    starting: color(248, 250, 255),
    ending: color(237, 243, 255)
)!
backgroundGradient.draw(in: backgroundRect, angle: -90)

color(41, 105, 255, alpha: 0.055).setFill()
NSBezierPath(ovalIn: NSRect(x: -90, y: 245, width: 310, height: 310)).fill()
color(133, 94, 255, alpha: 0.045).setFill()
NSBezierPath(ovalIn: NSRect(x: 500, y: -120, width: 280, height: 280)).fill()

let badgeRect = NSRect(x: 247, y: 348, width: 166, height: 30)
let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 15, yRadius: 15)
color(41, 105, 255, alpha: 0.1).setFill()
badgePath.fill()
drawCenteredText(
    "Noboard · 自在说  v\(version)",
    y: 356,
    font: .systemFont(ofSize: 12, weight: .semibold),
    color: color(28, 84, 215)
)

drawCenteredText(
    "拖到 Applications 完成安装",
    y: 304,
    font: .systemFont(ofSize: 23, weight: .semibold),
    color: color(28, 37, 56)
)
drawCenteredText(
    "Drag to Applications to install",
    y: 278,
    font: .systemFont(ofSize: 13, weight: .regular),
    color: color(93, 105, 128)
)

let arrow = NSBezierPath()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 265, y: 190))
arrow.line(to: NSPoint(x: 395, y: 190))
arrow.move(to: NSPoint(x: 378, y: 205))
arrow.line(to: NSPoint(x: 395, y: 190))
arrow.line(to: NSPoint(x: 378, y: 175))
color(41, 105, 255, alpha: 0.82).setStroke()
arrow.stroke()

drawCenteredText(
    "安装完成后，从“应用程序”打开自在说",
    y: 72,
    font: .systemFont(ofSize: 13, weight: .medium),
    color: color(78, 91, 116)
)
drawCenteredText(
    "支持 macOS 12 及更高版本 · Intel 与 Apple 芯片",
    y: 49,
    font: .systemFont(ofSize: 11, weight: .regular),
    color: color(126, 137, 158)
)

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("无法生成 DMG 背景图。\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("写入 DMG 背景图失败：\(error.localizedDescription)\n", stderr)
    exit(1)
}
