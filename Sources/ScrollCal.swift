import SwiftUI
import AppKit
import Combine
import ServiceManagement

// MARK: - 布局常量（手动滚动需要精确的月份高度，所以集中在这里）

private enum Layout {
    static let cellHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 1
    static let blockPadding: CGFloat = 3
    /// 一个月的高度：6 行 × 7 列 + 行间距 + 上下内边距
    static let monthBlockHeight: CGFloat = 6 * cellHeight + 5 * rowSpacing + 2 * blockPadding
    static let panelWidth: CGFloat = 268
    static let horizontalPadding: CGFloat = 8
    /// 视口高度 ≈ 一个月，所以一屏基本就是一个月
    static let viewportHeight: CGFloat = 197
    static var contentWidth: CGFloat { panelWidth - horizontalPadding * 2 }
}

// MARK: - 时钟：让「今天」高亮保持准确

final class Clock: ObservableObject {
    @Published var now = Date()
    private var cancellable: AnyCancellable?

    init() {
        cancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.now = date }
    }
}

// MARK: - 扁平化小按钮

private struct FlatButton<Label: View>: View {
    let help: String
    let shortcut: KeyboardShortcut?
    let activeColor: Color?
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovering = false

    init(
        help: String,
        shortcut: KeyboardShortcut? = nil,
        activeColor: Color? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.help = help
        self.shortcut = shortcut
        self.activeColor = activeColor
        self.action = action
        self.label = label
    }

    private var foreground: Color {
        if let activeColor { return activeColor }
        return hovering ? Color.primary : Color.secondary
    }

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(OptionalShortcut(shortcut: shortcut))
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct OptionalShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}

// MARK: - 滚轮设置与全局监听
// 全部放在静态存储里：滚轮回调永远读到最新的倍率，
// 也避免"每次渲染都往 @State 写窗口"造成的无限重绘。

private enum ScrollSettings {
    /// 滚动倍率
    static var factor: Double = 1.0
    /// 面板所在窗口（判断滚轮事件是否落在面板上）
    static weak var window: NSWindow?
    /// 全局只保留一个监听器
    private static var monitor: Any?

    static func install(_ handle: @escaping (NSEvent) -> Bool) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handle(event) ? nil : event
        }
    }

    static func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// 只在真正加入/离开窗口时回调，不做任何会触发重绘的写入
private final class WindowProbeView: NSView {
    var onWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindow?(window)
    }
}

private struct WindowProbe: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        view.onWindow = onWindow
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        nsView.onWindow = onWindow
    }
}

/// 离屏预览时不要挂 NSViewRepresentable，否则 ImageRenderer 会画"无法渲染"占位符
private struct WindowProbeBackground: ViewModifier {
    let enabled: Bool
    let onWindow: (NSWindow?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.background(WindowProbe(onWindow: onWindow))
        } else {
            content
        }
    }
}

// MARK: - 日期格子

private struct DayCell: View {
    let day: Int
    let label: String
    let labelKind: DayLabelKind
    let isToday: Bool
    let isOutsideMonth: Bool

    @State private var hovering = false

    private var background: Color {
        if isToday { return .accentColor }
        if hovering && !isOutsideMonth { return Color.primary.opacity(0.07) }
        return .clear
    }

    private var dayColor: Color {
        if isToday { return .white }
        if isOutsideMonth { return Color.primary.opacity(0.22) }   // 非本月整格灰掉
        return .primary
    }

    private var labelColor: Color {
        if isToday { return Color.white.opacity(0.9) }
        if isOutsideMonth { return Color.primary.opacity(0.16) }
        switch labelKind {
        case .festival, .solarTerm: return Color.primary.opacity(0.70)   // 节日/节气稍深
        case .lunarMonth: return Color.primary.opacity(0.50)
        case .lunarDay: return Color.primary.opacity(0.46)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(day)")
                .font(.system(size: 13, weight: isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(dayColor)

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(background)
        )
        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onHover { hovering = $0 }
    }
}

// MARK: - 一个月：6 行 × 7 列，含前后补位（灰掉）

private struct MonthBlock: View {
    let monthStart: Date
    let calendar: Calendar
    let today: Date

    /// 从周一起的 42 天，始终 6 行，保证每月高度一致
    private var cells: [Date] {
        let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: Layout.rowSpacing) {
            ForEach(0..<6, id: \.self) { week in
                GridRow {
                    ForEach(0..<7, id: \.self) { weekday in
                        let index = week * 7 + weekday
                        if index < cells.count {
                            let date = cells[index]
                            let label = ChineseCalendar.label(for: date, in: calendar)
                            DayCell(
                                day: calendar.component(.day, from: date),
                                label: label.text,
                                labelKind: label.kind,
                                isToday: calendar.isDate(date, inSameDayAs: today),
                                isOutsideMonth: !calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
                            )
                        }
                    }
                }
            }
        }
        .frame(height: Layout.monthBlockHeight)
        .padding(.horizontal, 2)
    }
}

// MARK: - 弹出面板

struct CalendarPanel: View {
    @ObservedObject var clock: Clock

    /// 仅用于离屏预览：只显示这一个月，并把该月 15 号当作"今天"
    private let previewMonth: Date?

    init(clock: Clock, previewMonth: Date? = nil) {
        self.clock = clock
        self.previewMonth = previewMonth
    }

    private let monthsBack = 36
    private let monthsForward = 24
    /// 可选的滚动倍率
    private let scrollFactors: [Double] = [0.2, 0.3, 0.5, 0.8, 1.0, 1.5, 2.0, 3.0]

    @State private var calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 2      // 周一为一周之始（与参考日历一致）
        return calendar
    }()
    @State private var launchAtLogin = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollFactor: Double = ScrollSettings.factor

    /// 面板的"当前时间"（正常运行时跟随系统时钟）
    private var referenceDate: Date { previewMonth == nil ? clock.now : previewMonth! }

    private var isPreview: Bool { previewMonth != nil }

    private var monthStarts: [Date] {
        let base = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) ?? referenceDate
        return (-(isPreview ? 0 : monthsBack)...(isPreview ? 0 : monthsForward)).compactMap {
            calendar.date(byAdding: .month, value: $0, to: base)
        }
    }

    private var todayIndex: Int { isPreview ? 0 : monthsBack }
    private var monthCount: Int { monthStarts.count }
    private var contentHeight: CGFloat { CGFloat(monthCount) * Layout.monthBlockHeight }
    private var maxOffset: CGFloat { max(0, contentHeight - Layout.viewportHeight) }

    /// 视口顶部对应的月份
    private var visibleIndex: Int {
        guard monthCount > 0 else { return 0 }
        let raw = Int((scrollOffset / Layout.monthBlockHeight).rounded())
        return max(0, min(monthCount - 1, raw))
    }

    /// 只渲染视口附近的几个月（手动虚拟化）
    private var renderRange: [Int] {
        guard monthCount > 0 else { return [] }
        return Array(max(0, visibleIndex - 1)...min(monthCount - 1, visibleIndex + 2))
    }

    private var visibleMonthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        let start = monthStarts.indices.contains(visibleIndex) ? monthStarts[visibleIndex] : referenceDate
        return formatter.string(from: start)
    }

    private var todayLunarText: String {
        ChineseCalendar.lunarDateText(for: referenceDate, in: calendar)
    }

    private var factorLabel: String {
        String(format: "%.1f×", scrollFactor)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let first = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 0) {
            // 第一行：农历今日 / 滚动倍率 / 打开日历 / 开机自启 / 退出
            HStack(spacing: 2) {
                FlatButton(
                    help: "定位今日 · 农历\(todayLunarText)（⌘T）",
                    shortcut: KeyboardShortcut("t", modifiers: .command)
                ) {
                    jumpToToday()
                } label: {
                    Text(todayLunarText)
                }

                Spacer(minLength: 4)

                FlatButton(help: "滚动倍率 \(factorLabel)：左键点一下换下一档，右键选择") {
                    cycleScrollFactor()
                } label: {
                    Text(factorLabel).monospacedDigit()
                }
                .contextMenu {
                    ForEach(scrollFactors, id: \.self) { value in
                        Button {
                            setScrollFactor(value)
                        } label: {
                            Text(String(format: "%.1f×", value))
                        }
                    }
                }

                FlatButton(help: "打开「日历」App") {
                    openCalendarApp()
                } label: {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 10))
                }

                FlatButton(
                    help: launchAtLogin ? "开机自启：已开启（点击关闭）" : "开机自启：未开启（点击开启）",
                    activeColor: launchAtLogin ? Color.accentColor : nil
                ) {
                    toggleLaunchAtLogin()
                } label: {
                    Image(systemName: launchAtLogin ? "powerplug.fill" : "powerplug")
                        .font(.system(size: 10))
                }

                FlatButton(help: "退出 ScrollCal（⌘Q）", shortcut: KeyboardShortcut("q", modifiers: .command)) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power").font(.system(size: 10))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            hairline

            // 第二行：年 + 月，右侧上/下月
            HStack(spacing: 2) {
                Text(visibleMonthTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.leading, 4)

                Spacer(minLength: 4)

                FlatButton(help: "上一月") { stepMonth(-1) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
                }

                FlatButton(help: "下一月") { stepMonth(1) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)

            // 第三行：星期
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.bottom, 3)

            hairline

            // 月份区：自己管滚动偏移，所以滚轮幅度可以按倍率缩放
            ZStack(alignment: .top) {
                ForEach(renderRange, id: \.self) { index in
                    MonthBlock(
                        monthStart: monthStarts[index],
                        calendar: calendar,
                        today: referenceDate
                    )
                    .frame(width: Layout.contentWidth, height: Layout.monthBlockHeight)
                    .offset(y: CGFloat(index) * Layout.monthBlockHeight - scrollOffset)
                }
            }
            .frame(width: Layout.contentWidth, height: Layout.viewportHeight, alignment: .top)
            .clipped()
            .padding(.horizontal, Layout.horizontalPadding)
        }
        .frame(width: Layout.panelWidth)
        .modifier(WindowProbeBackground(enabled: !isPreview) { window in
            ScrollSettings.window = window      // 静态写入，不会触发重绘
        })
        .onAppear {
            refreshLaunchAtLogin()
            installWheelMonitor()
            scrollFactor = ScrollSettings.factor     // 与静态设置保持一致
            scrollOffset = min(CGFloat(todayIndex) * Layout.monthBlockHeight, maxOffset)
        }
        .onDisappear {
            ScrollSettings.remove()
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    // MARK: 滚动

    private func applyScroll(delta: CGFloat, animated: Bool) {
        // 倍率从静态存储读取，保证永远是当前设置
        let next = min(max(0, scrollOffset - delta * CGFloat(ScrollSettings.factor)), maxOffset)
        guard abs(next - scrollOffset) > 0.01 else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.11)) { scrollOffset = next }
        } else {
            scrollOffset = next
        }
    }

    private func scroll(to index: Int, animated: Bool) {
        let target = min(max(0, index), monthCount - 1)
        let value = min(CGFloat(target) * Layout.monthBlockHeight, maxOffset)
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { scrollOffset = value }
        } else {
            scrollOffset = value
        }
    }

    private func stepMonth(_ delta: Int) {
        scroll(to: visibleIndex + delta, animated: true)
    }

    private func jumpToToday() {
        scroll(to: todayIndex, animated: true)
    }

    private func setScrollFactor(_ value: Double) {
        scrollFactor = value
        ScrollSettings.factor = value
    }

    private func cycleScrollFactor() {
        let current = scrollFactors.firstIndex(where: { abs($0 - scrollFactor) < 0.001 }) ?? 0
        setScrollFactor(scrollFactors[(current + 1) % scrollFactors.count])
    }

    // MARK: 滚轮监听
    // 面板里没有 ScrollView，滚动偏移由我们自己维护，所以能按倍率缩放幅度。

    private func installWheelMonitor() {
        #if !PREVIEW
        ScrollSettings.install { event in
            guard let window = ScrollSettings.window, event.window === window else { return false }

            if event.hasPreciseScrollingDeltas {
                // 触控板：连续像素级增量，直接跟手
                applyScroll(delta: event.scrollingDeltaY, animated: false)
            } else {
                // 鼠标滚轮：一格是"行"单位，放大到接近系统的滚动距离
                applyScroll(delta: event.scrollingDeltaY * 12, animated: true)
            }
            return true   // 消费掉，避免系统再滚一次
        }
        #endif
    }

    private func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    // MARK: 开机自启（SMAppService，不依赖自动化权限）

    private func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "设置开机自启失败"
            alert.informativeText = """
            \(error.localizedDescription)

            可以手动添加：系统设置 → 通用 → 登录项与扩展 → 添加 /Applications/ScrollCal.app
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
        refreshLaunchAtLogin()
    }
}

// MARK: - App

#if !PREVIEW
@main
struct ScrollCalApp: App {
    @StateObject private var clock = Clock()

    /// 菜单栏图标：比默认字号大一圈
    private var menuBarIcon: NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "日历")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }

    var body: some Scene {
        MenuBarExtra {
            CalendarPanel(clock: clock)
        } label: {
            Image(nsImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
#endif
