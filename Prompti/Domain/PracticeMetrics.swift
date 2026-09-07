import Foundation

enum PracticeMetrics {
    static func localDayKey(for date: Date = .now, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func consecutiveDayCount(dayKeys: [String], relativeTo now: Date = .now, timeZone: TimeZone = .current) -> Int {
        let days = Set(dayKeys)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(localDayKey(for: cursor, timeZone: timeZone)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(localDayKey(for: cursor, timeZone: timeZone)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func consecutiveDayCount(
        dates: [Date],
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let activeDays = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !activeDays.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        if !activeDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  activeDays.contains(yesterday) else {
                return 0
            }
            cursor = yesterday
        }

        var count = 0
        while activeDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
