import SwiftUI
import WidgetKit

@main
struct HabitTrackerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayRingWidget()
        StreakWidget()
        XPLevelWidget()
        ChecklistWidget()
        WeeklyWidget()
        FriendsProgressWidget()
        MentorDashboardWidget()
        MenteeViewWidget()
        DashboardWidget()
        LeaderboardWidget()
        AccountabilityPanelWidget()
        CommandCenterWidget()
    }
}
