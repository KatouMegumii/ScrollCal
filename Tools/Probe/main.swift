// 探针：确认 ImageRenderer 能否渲染 ScrollView / Grid / LazyVStack
import SwiftUI
import AppKit

try MainActor.assumeIsolated {
    _ = NSApplication.shared

    let probe = VStack(alignment: .leading, spacing: 10) {
        Text("1. ScrollView + VStack").font(.system(size: 11))
        ScrollView {
            VStack(spacing: 2) {
                Text("A1").font(.system(size: 12))
                Text("A2").font(.system(size: 12))
            }
        }
        .frame(width: 140, height: 50)
        .border(Color.red)

        Text("2. Grid + GridRow").font(.system(size: 11))
        Grid(horizontalSpacing: 4, verticalSpacing: 2) {
            GridRow { Text("B1"); Text("B2") }
            GridRow { Text("B3"); Text("B4") }
        }
        .font(.system(size: 12))
        .border(Color.blue)

        Text("3. 非惰性 VStack").font(.system(size: 11))
        VStack(spacing: 2) {
            Text("C1").font(.system(size: 12))
            Text("C2").font(.system(size: 12))
        }
        .border(Color.green)

        Text("4. LazyVStack").font(.system(size: 11))
        LazyVStack(spacing: 2) {
            Text("D1").font(.system(size: 12))
            Text("D2").font(.system(size: 12))
        }
        .border(Color.orange)
    }
    .padding(10)
    .background(Color.white)

    let renderer = ImageRenderer(content: probe)
    renderer.scale = 2

    if let image = renderer.nsImage,
       let tiff = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/probe.png"))
        print("probe 渲染完成")
    } else {
        print("probe 渲染失败")
        exit(1)
    }
}
