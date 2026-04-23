import Combine
import Foundation
@preconcurrency import UserNotifications

enum HabitReminderWindow: String, CaseIterable, Identifiable, Codable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        }
    }

    var hour: Int {
        switch self {
        case .morning: return 9
        case .afternoon: return 14
        case .evening: return 19
        }
    }

    var subtitle: String {
        switch self {
        case .morning: return "9 AM"
        case .afternoon: return "2 PM"
        case .evening: return "7 PM"
        }
    }
}

@MainActor
final class TimeReminderManager: ObservableObject {
    private let identifierPrefix = "time-reminder-"
    private let streakEndingIdentifier = "streak-ending-soon"

    /// Evening warning hour/minute for the streak-ending-soon nudge. Chosen
    /// late enough that the user had a real chance to check in during the day,
    /// early enough that a freeze is still a deliberate choice (not a panic
    /// 11:59 tap).
    private static let streakWarningHour = 21
    private static let streakWarningMinute = 30

    /// Schedules or cancels the single "streak ending soon — use a freeze"
    /// warning for tonight. Conditions: user has a streak to protect, still
    /// has incomplete habits today, owns at least one freeze, and hasn't
    /// already frozen today. Requests notification authorization if the user
    /// has never been asked.
    func refreshStreakEndingReminder(
        currentStreak: Int,
        hasIncompleteHabits: Bool,
        freezesAvailable: Int,
        isFrozenToday: Bool
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [streakEndingIdentifier])

        let shouldSchedule = currentStreak >= 1
            && hasIncompleteHabits
            && freezesAvailable >= 1
            && !isFrozenToday
        guard shouldSchedule else { return }

        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = Self.streakWarningHour
        components.minute = Self.streakWarningMinute
        guard let trigger = calendar.date(from: components),
              trigger > now.addingTimeInterval(60) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Streak ending soon"
        content.body = "Your \(currentStreak)-day streak is at risk. Tap to use a freeze and keep it alive."
        content.sound = .default

        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: trigger)
        let notificationTrigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: streakEndingIdentifier,
            content: content,
            trigger: notificationTrigger
        )

        requestAuthorizationIfNeeded { granted in
            guard granted else { return }
            center.add(request)
        }
    }

    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    completion(granted)
                }
            case .denied:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    func refreshReminders(for habits: [Habit], todayKey: String) {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let calendar = Calendar.current
        let plans = reminderPlans(for: habits, todayKey: todayKey, now: now, calendar: calendar)

        center.getPendingNotificationRequests { [identifierPrefix, plans] requests in
            let staleIdentifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }

            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)

            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default

                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.triggerDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(identifierPrefix)\(plan.windowRawValue)",
                    content: content,
                    trigger: trigger
                )

                center.add(request)
            }
        }
    }

    private func reminderPlans(
        for habits: [Habit],
        todayKey: String,
        now: Date,
        calendar: Calendar
    ) -> [ReminderPlan] {
        HabitReminderWindow.allCases.compactMap { window in
            let assigned = habits.filter { habit in
                !habit.isArchived
                    && habit.entryType == .habit
                    && habit.reminderWindow == window.rawValue
            }

            guard !assigned.isEmpty else { return nil }

            let triggerDate = Self.nextTriggerDate(for: window, from: now, calendar: calendar)
            let triggerIsToday = calendar.isDate(triggerDate, inSameDayAs: now)
            let reminderHabits = triggerIsToday
                ? assigned.filter { !$0.completedDayKeys.contains(todayKey) }
                : assigned

            guard !reminderHabits.isEmpty else { return nil }

            return ReminderPlan(
                windowRawValue: window.rawValue,
                title: "\(window.rawValue) habits",
                body: reminderHabits.count == 1
                    ? "Still open: \(reminderHabits[0].title)"
                    : "\(reminderHabits.count) habits are waiting for this window.",
                triggerDate: triggerDate
            )
        }
    }

    private static func nextTriggerDate(
        for window: HabitReminderWindow,
        from now: Date,
        calendar: Calendar
    ) -> Date {
        let today = calendar.date(
            bySettingHour: window.hour,
            minute: 0,
            second: 0,
            of: now
        ) ?? now

        if today > now.addingTimeInterval(60) {
            return today
        }

        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}

private struct ReminderPlan {
    let windowRawValue: String
    let title: String
    let body: String
    let triggerDate: Date
}
