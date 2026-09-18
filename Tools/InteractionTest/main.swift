// 交互自检：开一个真实窗口装面板，用合成鼠标事件点按钮。
// 只点"无副作用"的按钮（▲▼ 翻月、左上角农历定位），不会打开日历 App 或改登录项。
//
// 用法:
//   swiftc -O -DINTERACTION_TEST Sources/ScrollCal.swift Sources/ChineseCalendar.swift Tools/InteractionTest/main.swift -o build/interaction
//   ./build/interaction
// 复现旧行为（不做命中测试隔离）:
//   swiftc -O -DINTERACTION_TEST -DREPRO_OVERLAY_BUG ... -o build/interaction-repro && ./build/interaction-repro

import SwiftUI
import AppKit

try? MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let hosting = NSHostingView(rootView: CalendarPanel(clock: Clock()))
    hosting.layoutSubtreeIfNeeded()

    let fitting = hosting.fittingSize
    let panelSize = NSSize(
        width: fitting.width > 1 ? fitting.width : 268,
        height: fitting.height > 1 ? fitting.height : 265
    )
    hosting.frame = NSRect(origin: .zero, size: panelSize)
    print("面板尺寸: \(Int(panelSize.width))×\(Int(panelSize.height))")

    let window = NSWindow(
        contentRect: hosting.frame,
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = hosting
    window.setFrameOrigin(NSPoint(x: 60, y: 60))
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    RunLoop.current.run(until: Date().addingTimeInterval(1.0))

    func click(at point: NSPoint) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: timestamp, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ), let up = NSEvent.mouseEvent(
            with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: timestamp + 0.02, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 0
        ) else { return }

        window.sendEvent(down)
        window.sendEvent(up)
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
    }

    let row1Y = panelSize.height - 13        // 第一行按钮中心（AppKit 原点在左下）
    let row2Y = panelSize.height - 38        // 第二行（年月 + ▲▼）

    // ① 重绘频率
    PanelDebugState.bodyEvaluations = 0
    RunLoop.current.run(until: Date().addingTimeInterval(2.0))
    print("① 2 秒内 body 求值次数: \(PanelDebugState.bodyEvaluations)  (健康 < 100)")

    // ② 第二行的 ▲▼：扫描右侧，看滚动偏移是否变化
    let startOffset = PanelDebugState.scrollOffset
    var monthNavHits: [CGFloat] = []
    for x in stride(from: CGFloat(210), through: 260, by: 4) {
        let before = PanelDebugState.scrollOffset
        click(at: NSPoint(x: x, y: row2Y))
        if abs(PanelDebugState.scrollOffset - before) > 1 {
            monthNavHits.append(x)
        }
    }
    print("② 第二行 ▲▼ 可点中的 x: \(monthNavHits.map { Int($0) })  偏移 \(Int(startOffset)) → \(Int(PanelDebugState.scrollOffset))")

    // ③ 左上角农历按钮：先用 ▼ 确定性地翻走 3 个月，再点它，看是否回到今天所在月
    let todayOffset = startOffset
    let downX: CGFloat = 258
    for _ in 0..<3 {
        click(at: NSPoint(x: downX, y: row2Y))
    }
    let movedAway = abs(PanelDebugState.scrollOffset - todayOffset) > 1
    let movedBy = PanelDebugState.scrollOffset - todayOffset
    click(at: NSPoint(x: 30, y: row1Y))      // 农历按钮
    let backToToday = abs(PanelDebugState.scrollOffset - todayOffset) < 1
    print("③ ▼ 翻月后偏移变化 \(Int(movedBy))（动过=\(movedAway)），点农历按钮后回到 \(Int(todayOffset)) = \(backToToday)")

    let ok = !monthNavHits.isEmpty && movedAway && backToToday
    print(ok ? "结论: 按钮可点击、翻月与农历定位都有效 ✓" : "结论: 存在问题 ✗")

    window.orderOut(nil)
    exit(0)
}
