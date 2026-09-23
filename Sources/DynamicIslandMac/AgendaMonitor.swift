import AppKit
import Combine
import EventKit

/// A timed calendar event for today, as the island shows it.
struct AgendaEvent: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    /// A video-call link found in the event (Zoom, Meet, Teams, Telemost, Webex).
    let joinURL: URL?
}

/// An incomplete reminder that is due today or overdue.
struct AgendaReminder: Equatable {
    let id: String
    let title: String
    let due: Date?
}

/// Today's agenda as of the moment it was built.
struct AgendaSnapshot: Equatable {
    /// Not yet ended, by start time.
    var events: [AgendaEvent] = []
    /// Overdue first, then by due time.
    var reminders: [AgendaReminder] = []
    /// An event that started within the last `AgendaMonitor.nowWindow`.
    var nowEvent: AgendaEvent?
    /// A reminder that fell due within the last `AgendaMonitor.nowWindow`.
    var nowReminder: AgendaReminder?
}

/// One-off moments the island announces with a glance.
enum AgendaAlert {
    case upcoming(AgendaEvent, minutes: Int)
    case started(AgendaEvent)
    case due(AgendaReminder)
}

/// Today's events and reminders from the system Calendar and Reminders
/// (every account added to macOS: iCloud, Google, Exchange…), via EventKit.
///
/// Event-driven: reloads on `EKEventStoreChanged`, day change and settings
/// changes, and schedules one timer per upcoming moment (heads-up, start, due,
/// end of the "now" window) instead of polling.
final class AgendaMonitor {
    /// How long a started event or a due reminder stays "now" in the island.
    static let nowWindow: TimeInterval = 10 * 60

    private let store = EKEventStore()
    private let settings = IslandSettings.shared
    private var onSnapshot: ((AgendaSnapshot) -> Void)?
    private var onAlert: ((AgendaAlert) -> Void)?

    private var events: [AgendaEvent] = []
    private var reminders: [AgendaReminder] = []
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []
    private var settingsCancellable: AnyCancellable?
    /// Fake data from the debug server replaces EventKit until cleared.
    private(set) var isInjecting = false

    func start(
        onSnapshot: @escaping (AgendaSnapshot) -> Void,
        onAlert: @escaping (AgendaAlert) -> Void
    ) {
        self.onSnapshot = onSnapshot
        self.onAlert = onAlert

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                self?.reload()
            },
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            },
            // Timers don't fire during sleep; re-plan from the real clock.
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.reload()
            },
        ]
        // `objectWillChange` fires before the new value lands.
        settingsCancellable = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.requestAccessIfNeeded()
            }

        requestAccessIfNeeded()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        timers.forEach { $0.invalidate() }
    }

    // MARK: - Access

    var eventsAuthorization: String { Self.describe(EKEventStore.authorizationStatus(for: .event)) }
    var remindersAuthorization: String { Self.describe(EKEventStore.authorizationStatus(for: .reminder)) }

    /// Asks one permission at a time, so two system prompts never stack.
    private func requestAccessIfNeeded() {
        if settings.calendarEnabled, EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            store.requestFullAccessToEvents { [weak self] _, _ in
                DispatchQueue.main.async { self?.requestAccessIfNeeded() }
            }
            return
        }
        if settings.remindersEnabled, EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            store.requestFullAccessToReminders { [weak self] _, _ in
                DispatchQueue.main.async { self?.requestAccessIfNeeded() }
            }
            return
        }
        reload()
    }

    private static func describe(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: return "fullAccess"
        case .writeOnly: return "writeOnly"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Loading

    func reload() {
        guard !isInjecting else { return }
        let events = settings.calendarEnabled
            && EKEventStore.authorizationStatus(for: .event) == .fullAccess
            ? todaysEvents() : []

        guard settings.remindersEnabled,
              EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let endOfDay = Self.endOfToday()
        else {
            apply(events: events, reminders: [])
            return
        }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: endOfDay, calendars: nil
        )
        store.fetchReminders(matching: predicate) { [weak self] found in
            let reminders = (found ?? []).map {
                AgendaReminder(
                    id: $0.calendarItemIdentifier,
                    title: $0.title ?? "",
                    due: $0.dueDateComponents?.date
                )
            }
            DispatchQueue.main.async {
                guard let self, !self.isInjecting else { return }
                self.apply(events: events, reminders: reminders)
            }
        }
    }

    private func todaysEvents() -> [AgendaEvent] {
        guard let endOfDay = Self.endOfToday() else { return [] }
        let predicate = store.predicateForEvents(withStart: Date(), end: endOfDay, calendars: nil)
        return store.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay, event.status != .canceled else { return false }
                let me = event.attendees?.first { $0.isCurrentUser }
                return me?.participantStatus != .declined
            }
            .map {
                AgendaEvent(
                    id: $0.calendarItemIdentifier + "@" + String($0.startDate.timeIntervalSince1970),
                    title: $0.title ?? "",
                    start: $0.startDate,
                    end: $0.endDate,
                    joinURL: Self.joinURL(in: [$0.url?.absoluteString, $0.location, $0.notes])
                )
            }
    }

    private static let callHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "telemost.yandex", "webex.com",
    ]

    /// The first video-call link in any of the event's text fields.
    static func joinURL(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if callHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) || host.hasPrefix($0) }) {
                    return url
                }
            }
        }
        return nil
    }

    private static func endOfToday() -> Date? {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
    }

    // MARK: - Actions

    /// Ticks the reminder off in the Reminders app.
    func complete(reminderID: String) {
        if isInjecting {
            apply(events: events, reminders: reminders.filter { $0.id != reminderID })
            return
        }
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
        } catch {
            return
        }
        reload()
    }

    /// Debug server: plan fake events and reminders through the same path.
    func inject(events: [AgendaEvent], reminders: [AgendaReminder]) {
        isInjecting = true
        apply(events: events, reminders: reminders)
    }

    func clearInjection() {
        isInjecting = false
        reload()
    }

    // MARK: - Scheduling

    private func apply(events: [AgendaEvent], reminders: [AgendaReminder]) {
        self.events = events.sorted { $0.start < $1.start }
        self.reminders = reminders.sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
        reschedule()
    }

    private func reschedule() {
        timers.forEach { $0.invalidate() }
        timers = []
        let now = Date()
        let lead = settings.eventLeadMinutes * 60

        for event in events {
            let headsUp = event.start.addingTimeInterval(-lead)
            if headsUp > now {
                schedule(at: headsUp) { [weak self] in
                    // Fired late after sleep: a heads-up for something that
                    // already started is noise.
                    guard Date() < event.start else { return }
                    let minutes = Int((event.start.timeIntervalSinceNow / 60).rounded())
                    self?.onAlert?(.upcoming(event, minutes: max(1, minutes)))
                }
            }
            if event.start > now {
                schedule(at: event.start) { [weak self] in
                    guard Date() < event.start.addingTimeInterval(60) else { return }
                    self?.onAlert?(.started(event))
                    self?.emit()
                }
            }
            let nowEnds = min(event.end, event.start.addingTimeInterval(Self.nowWindow))
            if nowEnds > now { schedule(at: nowEnds) { [weak self] in self?.emit() } }
            if event.end > now { schedule(at: event.end) { [weak self] in self?.emit() } }
        }

        for reminder in reminders {
            guard let due = reminder.due else { continue }
            if due > now {
                schedule(at: due) { [weak self] in
                    guard Date() < due.addingTimeInterval(60) else { return }
                    self?.onAlert?(.due(reminder))
                    self?.emit()
                }
            }
            let nowEnds = due.addingTimeInterval(Self.nowWindow)
            if nowEnds > now { schedule(at: nowEnds) { [weak self] in self?.emit() } }
        }

        emit()
    }

    private func schedule(at date: Date, _ action: @escaping () -> Void) {
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    private func emit() {
        let now = Date()
        let upcoming = events.filter { $0.end > now }
        let nowEvent = upcoming.first {
            $0.start <= now && now < min($0.end, $0.start.addingTimeInterval(Self.nowWindow))
        }
        let nowReminder = reminders.first {
            guard let due = $0.due else { return false }
            return due <= now && now < due.addingTimeInterval(Self.nowWindow)
        }
        onSnapshot?(AgendaSnapshot(
            events: upcoming,
            reminders: reminders,
            nowEvent: nowEvent,
            nowReminder: nowReminder
        ))
    }
}

#if DEBUG
extension AgendaMonitor {
    static let testListTitle = "DynamicIsland QA"

    /// Live check of the real EventKit path: one reminder in a list of its
    /// own, so nothing of the user's is touched.
    func createTestReminder(title: String, dueIn: TimeInterval) -> String? {
        guard let source = store.defaultCalendarForNewReminders()?.source else { return nil }
        let list = store.calendars(for: .reminder).first { $0.title == Self.testListTitle }
            ?? {
                let list = EKCalendar(for: .reminder, eventStore: store)
                list.title = Self.testListTitle
                list.source = source
                try? store.saveCalendar(list, commit: true)
                return list
            }()
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date().addingTimeInterval(dueIn)
        )
        do {
            try store.save(reminder, commit: true)
        } catch {
            return nil
        }
        return reminder.calendarItemIdentifier
    }

    /// Whether the test reminder is completed, then removes the test list.
    func removeTestData() -> [String: Any] {
        guard let list = store.calendars(for: .reminder).first(where: { $0.title == Self.testListTitle }) else {
            return ["removed": false]
        }
        do {
            try store.removeCalendar(list, commit: true)
        } catch {
            return ["removed": false, "error": "\(error)"]
        }
        return ["removed": true]
    }

    func testReminderCompleted(id: String) -> Bool? {
        (store.calendarItem(withIdentifier: id) as? EKReminder)?.isCompleted
    }
}
#endif
