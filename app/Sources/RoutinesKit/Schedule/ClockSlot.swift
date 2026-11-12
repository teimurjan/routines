import Foundation

/// A launchd-style calendar slot. A field that is nil matches each value. `weekday` counts from Sunday as 0.
public struct ClockSlot: Codable, Equatable, Hashable, Sendable {
    public var minute: Int?
    public var hour: Int?
    public var weekday: Int?
    public var day: Int?

    public init(minute: Int? = nil, hour: Int? = nil, weekday: Int? = nil, day: Int? = nil) {
        self.minute = minute
        self.hour = hour
        self.weekday = weekday
        self.day = day
    }

    public func matches(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.minute, .hour, .weekday, .day], from: date)
        return Self.fits(minute, parts.minute) && Self.fits(hour, parts.hour) && Self.fits(weekday, parts.weekday.map { $0 - 1 })
            && Self.fits(day, parts.day)
    }

    private static func fits(_ wanted: Int?, _ actual: Int?) -> Bool {
        guard let wanted else { return true }
        return wanted == actual
    }
}

public enum Schedule {
    /// The longest gap that the host looks back over after a sleep. A slot in it makes one run, as launchd does.
    static let maxLookBack: TimeInterval = 2 * 24 * 60 * 60

    /// True if a minute in the half-open range (after, until] matches a slot.
    public static func isDue(_ slots: [ClockSlot], after: Date, until: Date, calendar: Calendar = .current) -> Bool {
        guard !slots.isEmpty, until > after else { return false }
        let start = max(after, until.addingTimeInterval(-maxLookBack))
        guard var minute = calendar.dateInterval(of: .minute, for: start)?.start else { return false }
        if minute <= after { minute = minute.addingTimeInterval(60) }
        while minute <= until {
            if slots.contains(where: { $0.matches(minute, calendar: calendar) }) { return true }
            minute = minute.addingTimeInterval(60)
        }
        return false
    }
}
