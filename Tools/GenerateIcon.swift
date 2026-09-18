// 生成 App 图标所需的各尺寸 PNG（写入 .iconset 目录）
// 用法: swift GenerateIcon.swift <输出目录>
// 图形与菜单栏图标一致：SF Symbol "calendar" + 扁平圆角方形底

import AppKit
import Foundation

// MARK: - 参数

let blueTop = NSColor(srgbRed: 0.36, green: 0.63, blue: 1.00, alpha: 1)
let blueBottom = NSColor(srgbRed: 0.06, green: 0.40, blue: 0.90, alpha: 1)

/// macOS 应用图标留白与圆角比例（对齐 Apple 的 824/1024 网格）
let canvasInsetRatio: CGFloat = 0.098
let cornerRadiusRatio: CGFloat = 0.225
/// 日历图形占底色的比例
let glyphRatio: CGFloat = 0.60

func renderIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)

    guard let rep = NSBitmapImageRep(
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
    ) else {
        fatalError("无法创建位图 \(pixels)px")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
    }

    // 1. 圆角方形底 + 竖向渐变
    let inset = size * canvasInsetRatio
    let shape = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = shape.width * cornerRadiusRatio
    let shapePath = NSBezierPath(roundedRect: shape, xRadius: radius, yRadius: radius)

    if let gradient = NSGradient(starting: blueTop, ending: blueBottom) {
        gradient.draw(in: shapePath, angle: -90)
    }

    // 2. 日历图形（白色）
    let box = shape.width * glyphRatio
    let weight: NSFont.Weight = pixels <= 128 ? .medium : .regular

    let configuration = NSImage.SymbolConfiguration(pointSize: box, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

    if let symbol = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {

        let natural = symbol.size
        let scale = min(box / max(natural.width, 1), box / max(natural.height, 1))
        let drawSize = NSSize(width: natural.width * scale, height: natural.height * scale)
        let drawRect = NSRect(
            x: shape.midX - drawSize.width / 2,
            y: shape.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    // 3. 顶部一圈极淡高光，边界更利落
    NSColor.white.withAlphaComponent(0.16).setStroke()
    let border = NSBezierPath(
        roundedRect: shape.insetBy(dx: 0.5, dy: 0.5),
        xRadius: radius,
        yRadius: radius
    )
    border.lineWidth = max(1, size * 0.004)
    border.stroke()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG 编码失败 \(pixels)px")
    }
    return data
}

// MARK: - 主流程

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write("用法: swift GenerateIcon.swift <iconset 输出目录>\n".data(using: .utf8)!)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// 像素尺寸 -> iconset 文件名（同一个位图可复用多个名字）
let pixelSizes = [16, 32, 64, 128, 256, 512, 1024]
var rendered: [Int: Data] = [:]

for pixels in pixelSizes {
    rendered[pixels] = renderIcon(pixels: pixels)
}

let iconSetNames: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for entry in iconSetNames {
    guard let data = rendered[entry.pixels] else { continue }
    try data.write(to: outputDirectory.appendingPathComponent(entry.name))
}

print("已生成 \(iconSetNames.count) 个 PNG 到 \(outputDirectory.path)")
