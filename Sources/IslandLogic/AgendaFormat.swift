import Foundation

public enum AgendaFormat {
    /// What the collapsed island shows beside an event's icon.
    public enum CollapsedLabel: Equatable {
        /// Not started yet: its start time.
        case startsAt(Date)
        /// Under way and ending within the hour: whole minutes left (at least 1).
        case minutesLeft(Int)
        /// Under way for more than an hour yet: its end time.
        case endsAt(Date)
    }

    public static func collapsedLabel(start: Date, end: Date, now: Date) -> CollapsedLabel {
        guard now >= start else { return .startsAt(start) }
        let left = end.timeIntervalSince(now)
        guard left < 3600 else { return .endsAt(end) }
        return .minutesLeft(max(1, Int((left / 60).rounded(.up))))
    }

    /// Reminders for the expanded list. The due-now reminder only gets the
    /// header when no event holds it; otherwise it must stay in the list, or an
    /// overdue reminder vanishes during a meeting.
    public static func listedReminders<R: Equatable>(_ reminders: [R], nowReminder: R?, hasNowEvent: Bool) -> [R] {
        guard !hasNowEvent, let nowReminder else { return reminders }
        return reminders.filter { $0 != nowReminder }
    }
}
