import Combine
import Foundation
import Network

/// Publishes connectivity state by wrapping `NWPathMonitor`. Views and stores
/// observe `isOnline` so the app can suppress network errors when offline and
/// auto-trigger a sync when connectivity returns.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "forma.networkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isOnline != online { self.isOnline = online }
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
