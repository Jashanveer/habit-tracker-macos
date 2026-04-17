import Combine
import CoreWLAN
import Foundation
import UserNotifications

// Monitors active Wi-Fi SSID changes and fires local notifications for habits
// whose reminder context matches the current network label.
@MainActor
final class LocationReminderManager: ObservableObject {
    @Published private(set) var currentSSID: String?

    // Maps Wi-Fi SSID → location label (set by user in settings)
    // Persisted in UserDefaults key "habitTracker.wifiLabels"
    @Published var wifiLabels: [String: LocationContext] = [:]

    @Published var currentContext: LocationContext = .unknown

    private var timer: Timer?

    init() { loadLabels(); startPolling() }
    deinit { timer?.invalidate() }

    func labelSSID(_ ssid: String, as context: LocationContext) {
        wifiLabels[ssid] = context
        saveLabels()
        updateContext()
    }

    func removeLabel(for ssid: String) {
        wifiLabels.removeValue(forKey: ssid)
        saveLabels()
        updateContext()
    }

    private func startPolling() {
        // Poll every 60s — CoreWLAN doesn't have a reliable delegate on macOS 26
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.refreshSSID() }
        }
        refreshSSID()
    }

    private func refreshSSID() {
        let ssid = CWWiFiClient.shared().interface()?.ssid()
        if ssid != currentSSID {
            currentSSID = ssid
            updateContext()
        }
    }

    private func updateContext() {
        guard let ssid = currentSSID else { currentContext = .unknown; return }
        currentContext = wifiLabels[ssid] ?? .unknown
    }

    private func saveLabels() {
        let raw = wifiLabels.reduce(into: [String: String]()) { $0[$1.key] = $1.value.rawValue }
        UserDefaults.standard.set(raw, forKey: "habitTracker.wifiLabels")
    }

    private func loadLabels() {
        let raw = UserDefaults.standard.dictionary(forKey: "habitTracker.wifiLabels") as? [String: String] ?? [:]
        wifiLabels = raw.compactMapValues { LocationContext(rawValue: $0) }
    }
}

enum LocationContext: String, CaseIterable, Identifiable {
    case home = "Home"
    case work = "Work"
    case gym = "Gym"
    case other = "Other"
    case unknown = "Unknown"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "building.2.fill"
        case .gym: return "dumbbell.fill"
        case .other: return "mappin.circle.fill"
        case .unknown: return "wifi.slash"
        }
    }
}
