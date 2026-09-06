import Foundation

enum PracticeMetrics {
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
