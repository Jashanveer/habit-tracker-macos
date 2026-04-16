import SwiftUI
import SwiftData

@main
struct HabitTrackerMacosApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Habit.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
    }
}
