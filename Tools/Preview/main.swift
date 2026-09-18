// 离屏渲染预览：把面板直接画成 PNG，用来检查排版（不需要点菜单栏、不需要截图权限）
// 用法: swiftc -DPREVIEW Sources/ScrollCal.swift Sources/ChineseCalendar.swift Tools/Preview/main.swift -o build/preview
//       ./build/preview <输出png> [light|dark] [年] [月]

import SwiftUI
import AppKit

try MainActor.assumeIsolated {
    _ = NSApplication.shared

    let arguments = CommandLine.arguments
    let outputPath = arguments.count > 1 ? arguments[1] : "build/preview.png"
    let schemeName = arguments.count > 2 ? arguments[2] : "light"
    let year = arguments.count > 3 ? (Int(arguments[3]) ?? 2026) : 2026
    let month = arguments.count > 4 ? (Int(arguments[4]) ?? 10) : 10

    var calendar = Calendar.current
    calendar.firstWeekday = 2

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 15
    components.hour = 12

    guard let focus = calendar.date(from: components) else {
        print("日期无效")
        exit(1)
    }

    let panel = CalendarPanel(clock: Clock(), previewMonth: focus)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, schemeName == "dark" ? .dark : .light)

    let renderer = ImageRenderer(content: panel)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("渲染失败")
        exit(1)
    }

    try png.write(to: URL(fileURLWithPath: outputPath))
    print("已写出 \(outputPath) — \(Int(image.size.width))×\(Int(image.size.height)) pt (\(year)年\(month)月, \(schemeName))")
}
