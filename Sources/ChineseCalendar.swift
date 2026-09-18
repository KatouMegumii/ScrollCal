// 农历 / 二十四节气 / 传统节日 —— 纯 Foundation 实现，无网络、无第三方依赖
//
// 农历：用 Foundation 内置的 Chinese calendar 换算
// 节气：用太阳视黄经求解（Meeus《Astronomical Algorithms》低精度公式），
//       精度约 0.01°（约 15 分钟），对"落在哪一天"足够，且正确覆盖 1900–2100 前后

import Foundation

// MARK: - 小字文案

enum DayLabelKind {
    case festival     // 农历传统节日（中秋节、重阳节…）
    case solarTerm    // 二十四节气（秋分、寒露…）
    case lunarMonth   // 农历初一（显示月名，如"九月"）
    case lunarDay     // 普通农历日（初二、廿三…）
}

struct DayLabel {
    let text: String
    let kind: DayLabelKind
}

// MARK: - 换算

enum ChineseCalendar {

    // MARK: 常量

    private static let lunarDayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
    ]

    private static let lunarMonthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月",
    ]

    /// 公历节日，键为"月-日"（优先级最高）
    private static let solarFestivals: [String: String] = [
        "1-1": "元旦",
        "2-14": "情人节",
        "3-8": "妇女节",
        "3-12": "植树节",
        "4-1": "愚人节",
        "5-1": "劳动节",
        "5-4": "青年节",
        "6-1": "儿童节",
        "7-1": "建党节",
        "8-1": "建军节",
        "9-10": "教师节",
        "10-1": "国庆节",
        "12-25": "圣诞节",
    ]

    /// 农历节日，键为"月-日"，闰月不适用
    private static let lunarFestivals: [String: String] = [
        "1-1": "春节",
        "1-15": "元宵节",
        "2-2": "龙抬头",
        "5-5": "端午节",
        "7-7": "七夕节",
        "8-15": "中秋节",
        "9-9": "重阳节",
        "12-8": "腊八节",
        "12-23": "小年",
    ]

    /// 二十四节气：名称 + 太阳视黄经（度）
    private static let solarTerms: [(name: String, longitude: Double)] = [
        ("小寒", 285), ("大寒", 300), ("立春", 315), ("雨水", 330),
        ("惊蛰", 345), ("春分", 0), ("清明", 15), ("谷雨", 30),
        ("立夏", 45), ("小满", 60), ("芒种", 75), ("夏至", 90),
        ("小暑", 105), ("大暑", 120), ("立秋", 135), ("处暑", 150),
        ("白露", 165), ("秋分", 180), ("寒露", 195), ("霜降", 210),
        ("立冬", 225), ("小雪", 240), ("大雪", 255), ("冬至", 270),
    ]

    // MARK: 缓存

    private static let lunarCalendar: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = TimeZone.current
        return calendar
    }()

    /// 年份 -> [月*100+日: 节气名]
    private static var termCache: [Int: [Int: String]] = [:]
    /// 当日零点时间戳 -> 文案
    private static var labelCache: [Int: DayLabel] = [:]

    // MARK: 对外接口

    /// 某一天的小字文案（优先级：农历节日 > 节气 > 农历初一显示月名 > 农历日）
    static func label(for date: Date, in calendar: Calendar) -> DayLabel {
        let key = Int(date.timeIntervalSince1970)
        if let cached = labelCache[key] { return cached }
        let computed = computeLabel(for: date, in: calendar)
        labelCache[key] = computed
        return computed
    }

    /// 该日若为节气则返回节气名
    static func solarTermName(for date: Date, in calendar: Calendar) -> String? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return terms(inYear: year, calendar: calendar)[month * 100 + day]
    }

    /// 农历日期文本，例如"八月初八"、"闰四月初一"
    static func lunarDateText(for date: Date, in calendar: Calendar) -> String {
        let parts = lunarCalendar.dateComponents([.month, .day, .isLeapMonth], from: date)
        let month = max(1, min(12, parts.month ?? 1))
        let day = max(1, min(30, parts.day ?? 1))
        let monthName = lunarMonthNames[month - 1]
        return ((parts.isLeapMonth ?? false) ? "闰\(monthName)" : monthName) + lunarDayNames[day - 1]
    }

    // MARK: 文案计算

    private static func computeLabel(for date: Date, in calendar: Calendar) -> DayLabel {
        // 1. 公历节日（优先级最高）
        let gregorian = calendar.dateComponents([.month, .day], from: date)
        if let month = gregorian.month, let day = gregorian.day {
            if let festival = solarFestivals["\(month)-\(day)"] {
                return DayLabel(text: festival, kind: .festival)
            }
        }

        // 2. 按星期推算的公历节日（母亲节 / 父亲节 / 感恩节）
        if let festival = weekdayFestival(for: date, in: calendar) {
            return DayLabel(text: festival, kind: .festival)
        }

        let parts = lunarCalendar.dateComponents([.month, .day, .isLeapMonth], from: date)
        let lunarMonth = parts.month ?? 1
        let lunarDay = parts.day ?? 1
        let isLeapMonth = parts.isLeapMonth ?? false

        // 3. 农历传统节日
        if !isLeapMonth, let festival = lunarFestivals["\(lunarMonth)-\(lunarDay)"] {
            return DayLabel(text: festival, kind: .festival)
        }

        // 4. 除夕 = 腊月最后一天（次日为正月初一）
        if !isLeapMonth, lunarMonth == 12,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
            let next = lunarCalendar.dateComponents([.month, .day], from: tomorrow)
            if next.month == 1 && next.day == 1 {
                return DayLabel(text: "除夕", kind: .festival)
            }
        }

        // 5. 二十四节气
        if let term = solarTermName(for: date, in: calendar) {
            return DayLabel(text: term, kind: .solarTerm)
        }

        // 6. 农历初一显示月名
        if lunarDay == 1 {
            let name = lunarMonthNames[max(0, min(11, lunarMonth - 1))]
            return DayLabel(text: isLeapMonth ? "闰\(name)" : name, kind: .lunarMonth)
        }

        // 7. 普通农历日
        return DayLabel(text: lunarDayNames[max(0, min(29, lunarDay - 1))], kind: .lunarDay)
    }

    /// 母亲节（5 月第 2 个周日）、父亲节（6 月第 3 个周日）、感恩节（11 月第 4 个周四）
    private static func weekdayFestival(for date: Date, in calendar: Calendar) -> String? {
        let parts = calendar.dateComponents([.month, .weekday, .weekdayOrdinal], from: date)
        guard let month = parts.month,
              let weekday = parts.weekday,
              let ordinal = parts.weekdayOrdinal else { return nil }

        switch (month, weekday, ordinal) {
        case (5, 1, 2): return "母亲节"
        case (6, 1, 3): return "父亲节"
        case (11, 5, 4): return "感恩节"
        default: return nil
        }
    }

    // MARK: 节气求解

    private static func terms(inYear year: Int, calendar: Calendar) -> [Int: String] {
        if let cached = termCache[year] { return cached }

        var table: [Int: String] = [:]
        for term in solarTerms {
            let jd = julianDay(forLongitude: term.longitude, year: year)
            // TD -> UT：2026 年前后 ΔT ≈ 69 秒，本用途可忽略其误差
            let epoch = (jd - 69.0 / 86400.0 - 2440587.5) * 86400.0
            let parts = calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: epoch))
            if let month = parts.month, let day = parts.day {
                table[month * 100 + day] = term.name
            }
        }

        termCache[year] = table
        return table
    }

    /// 太阳视黄经（度），Meeus 低精度公式，误差约 0.01°
    private static func apparentSolarLongitude(julianDay jd: Double) -> Double {
        let t = (jd - 2451545.0) / 36525.0
        let l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        let m = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) * .pi / 180
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m)
            + (0.019993 - 0.000101 * t) * sin(2 * m)
            + 0.000289 * sin(3 * m)
        let trueLongitude = l0 + c
        let omega = (125.04 - 1934.136 * t) * .pi / 180
        return trueLongitude - 0.00569 - 0.00478 * sin(omega)
    }

    /// 求某年太阳视黄经等于指定值的儒略日（TD）
    private static func julianDay(forLongitude longitude: Double, year: Int) -> Double {
        var offset = (longitude - 280.0).truncatingRemainder(dividingBy: 360.0)
        if offset < 0 { offset += 360 }

        // 初始估计：J2000 时太阳黄经约 280°
        var jd = 2451545.0 + Double(year - 2000) * 365.2422 + offset / 360.0 * 365.2422

        for _ in 0..<8 {
            var diff = apparentSolarLongitude(julianDay: jd) - longitude
            diff = diff.truncatingRemainder(dividingBy: 360.0)
            if diff > 180 { diff -= 360 }
            if diff < -180 { diff += 360 }
            jd -= diff / 0.9856473   // 太阳日均行度
        }
        return jd
    }
}
