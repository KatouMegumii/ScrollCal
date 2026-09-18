// 命令行校验工具：打印某年某月的日历网格（日期 + 农历/节气/节日）
// 用法: swiftc Sources/ChineseCalendar.swift Tools/CalendarDump/main.swift -o build/caldump && ./build/caldump 2026 10

import Foundation

var calendar = Calendar.current
calendar.firstWeekday = 2   // 周一起始

let arguments = CommandLine.arguments
let year = arguments.count > 1 ? (Int(arguments[1]) ?? 2026) : 2026
let month = arguments.count > 2 ? (Int(arguments[2]) ?? 10) : 10

var components = DateComponents()
components.year = year
components.month = month
components.day = 1
components.hour = 12

guard let monthStart = calendar.date(from: components),
      let range = calendar.range(of: .day, in: .month, for: monthStart) else {
    print("日期无效")
    exit(1)
}

// 网格起点（周一）
let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart)!

let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

print("\(year)年\(month)月   共 \(range.count) 天   （周一起始）")
print(weekdayNames.map { $0.padding(toLength: 12, withPad: " ", startingAt: 0) }.joined())

for week in 0..<6 {
    var numberLine: [String] = []
    var labelLine: [String] = []

    for weekday in 0..<7 {
        let offset = week * 7 + weekday
        guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { continue }
        let day = calendar.component(.day, from: date)
        let isOutside = !calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
        let label = ChineseCalendar.label(for: date, in: calendar).text

        var token = "\(day)"
        if isOutside { token = "·\(day)" }          // 非本月用 · 标记
        numberLine.append(token.padding(toLength: 12, withPad: " ", startingAt: 0))
        labelLine.append(label.padding(toLength: 12, withPad: " ", startingAt: 0))
    }

    print(numberLine.joined())
    print(labelLine.joined())
}

// 单日查询模式：./build/caldump 2026 10 1
if arguments.count > 3, let day = Int(arguments[3]) {
    components.day = day
    if let date = calendar.date(from: components) {
        let label = ChineseCalendar.label(for: date, in: calendar)
        let lunar = ChineseCalendar.lunarDateText(for: date, in: calendar)
        print("\n\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day)) => 大字「\(label.text)」 农历「\(lunar)」")
    }
}
