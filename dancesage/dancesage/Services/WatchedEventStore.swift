import Foundation
import Combine
import UserNotifications

@MainActor
final class WatchedEventStore: ObservableObject {
    @Published private(set) var events: [DanceEvent] = []
    private let storageKey = "watchedDanceEvents.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([DanceEvent].self, from: data) {
            events = saved
        }
    }

    func contains(_ event: DanceEvent) -> Bool { events.contains { $0.id == event.id } }

    func toggle(_ event: DanceEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events.remove(at: index)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [event.id])
        } else {
            events.append(event)
            events.sort { $0.startTime < $1.startTime }
            Task { await scheduleReminder(for: event) }
        }
        persist()
    }

    func remove(at offsets: IndexSet) {
        let identifiers = offsets.compactMap { events.indices.contains($0) ? events[$0].id : nil }
        for index in offsets.sorted(by: >) where events.indices.contains(index) {
            events.remove(at: index)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func scheduleReminder(for event: DanceEvent) async {
        guard event.startTime > Date() else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let reminderDate = max(Date().addingTimeInterval(60), event.startTime.addingTimeInterval(-7_200))
        let content = UNMutableNotificationContent()
        content.title = "Dance tonight"
        content.body = "(event.name) starts soon at (event.venueName). Check the source before leaving."
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: event.id, content: content, trigger: trigger))
    }
}
