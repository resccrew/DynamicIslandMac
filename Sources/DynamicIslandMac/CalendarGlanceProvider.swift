import EventKit
import Foundation

struct CalendarEvent {
    let title: String
    let timeRange: String
}

/// One-shot, best-effort lookup of the next calendar event today, for the
/// menu bar's "Ближайшее событие" glance. Same graceful-fallback pattern as
/// `LyricsProvider`: a denied permission or an empty calendar just yields
/// nil rather than surfacing an error in the UI.
enum CalendarGlanceProvider {
    private static let store = EKEventStore()

    static func fetchNextEvent(completion: @escaping (CalendarEvent?) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            guard granted else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let event = nextEvent()
            DispatchQueue.main.async { completion(event) }
        }
    }

    private static func nextEvent() -> CalendarEvent? {
        let calendar = Calendar.current
        let now = Date()
        guard let endOfDay = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: now)
        ) else { return nil }

        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        guard let next = store.events(matching: predicate)
            .sorted(by: { $0.startDate < $1.startDate })
            .first
        else { return nil }

        return CalendarEvent(
            title: next.title ?? "",
            timeRange: "\(formatter.string(from: next.startDate)) - \(formatter.string(from: next.endDate))"
        )
    }
}
