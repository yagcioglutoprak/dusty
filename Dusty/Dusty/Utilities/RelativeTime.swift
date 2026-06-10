import Foundation

/// Human phrasing for "when did this happen" labels. A menu bar app runs for
/// weeks, so an absolute clock time ("14:32") with no date reads as today even
/// when the event was days ago. Relative wording can't mislead that way.
enum RelativeTime {
    static func label(for date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 90 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
