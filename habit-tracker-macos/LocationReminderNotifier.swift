import Foundation
import UserNotifications

@MainActor
final class LocationReminderNotifier {
    private var lastNotifiedContext: LocationContext = .unknown
    private var lastNotifiedAt: Date?

    // Call this whenever context changes
    func contextDidChange(to context: LocationContext, habits: [Habit], todayKey: String) {
        guard context != .unknown, context != lastNotifiedContext else { return }
        // Don't spam — minimum 30 min between context notifications
        if let last = lastNotifiedAt, Date().timeIntervalSince(last) < 1800 { return }

        let relevant = habits.filter { h in
            h.locationContext == context.rawValue && !h.completedDayKeys.contains(todayKey)
        }
        guard !relevant.isEmpty else { return }

        lastNotifiedContext = context
        lastNotifiedAt = Date()

        let content = UNMutableNotificationContent()
        content.title = "\(context.rawValue) habits"
        content.body = relevant.count == 1
            ? "Don't forget: \(relevant[0].title)"
            : "\(relevant.count) habits waiting for you at \(context.rawValue.lowercased())."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "location-reminder-\(context.rawValue)",
            content: content,
            trigger: nil   // immediate
        )
        UNUserNotificationCenter.current().add(request)
    }
}
