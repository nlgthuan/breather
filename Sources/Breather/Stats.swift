import Foundation

/// Light, guilt-free stats: breaks taken vs. offered per day, and a streak.
@MainActor
final class Stats: ObservableObject {
    static let shared = Stats()

    struct Day: Codable { var taken = 0; var offered = 0 }

    @Published private(set) var days: [String: Day] = [:]
    private let key = "stats.days"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Day].self, from: data) {
            days = decoded
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var today: Day { days[Self.dayKey(Date())] ?? Day() }

    /// Consecutive days (ending today, or yesterday if nothing yet today) with at least one break taken.
    var streak: Int {
        let cal = Calendar.current
        var date = Date()
        if (days[Self.dayKey(date)]?.taken ?? 0) == 0 {
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        var count = 0
        while (days[Self.dayKey(date)]?.taken ?? 0) > 0 {
            count += 1
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }

    func record(taken: Bool) {
        let k = Self.dayKey(Date())
        var d = days[k] ?? Day()
        d.offered += 1
        if taken { d.taken += 1 }
        days[k] = d
        // Keep roughly the last 90 days.
        if days.count > 90 {
            for old in days.keys.sorted().prefix(days.count - 90) { days[old] = nil }
        }
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
