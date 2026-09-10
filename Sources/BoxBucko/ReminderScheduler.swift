import Foundation

/// A single reminder: some text, and when to say it.
struct Reminder: Codable, Identifiable, Equatable {
    let id: UUID
    var message: String
    var fireDate: Date

    init(id: UUID = UUID(), message: String, fireDate: Date) {
        self.id = id
        self.message = message
        self.fireDate = fireDate
    }
}

/// Lightweight reminders: "remind me in N minutes to do X." Persisted to
/// UserDefaults (as plain JSON) so a reminder set before quitting/restarting
/// BoxBucko still fires later, same as the rest of the app's UserDefaults-backed
/// state in `Preferences`.
final class ReminderScheduler {
    private(set) var pending: [Reminder] = []
    /// Fired on the main run loop when a reminder comes due.
    var onFire: ((Reminder) -> Void)?

    private var checkTimer: Timer?
    private let defaultsKey = "boxbucko.reminders"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func start() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkDue()
        }
        checkDue()
    }

    @discardableResult
    func schedule(message: String, minutesFromNow: Int) -> Reminder {
        let reminder = Reminder(message: message, fireDate: Date().addingTimeInterval(TimeInterval(minutesFromNow * 60)))
        pending.append(reminder)
        pending.sort { $0.fireDate < $1.fireDate }
        save()
        return reminder
    }

    func cancel(_ reminder: Reminder) {
        pending.removeAll { $0.id == reminder.id }
        save()
    }

    private func checkDue() {
        guard !pending.isEmpty else { return }
        let now = Date()
        let due = pending.filter { $0.fireDate <= now }
        guard !due.isEmpty else { return }
        pending.removeAll { reminder in due.contains(reminder) }
        save()
        for reminder in due.sorted(by: { $0.fireDate < $1.fireDate }) {
            onFire?(reminder)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        pending = decoded.sorted { $0.fireDate < $1.fireDate }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
