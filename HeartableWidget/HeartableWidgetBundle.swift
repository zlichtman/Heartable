import SwiftUI
import WidgetKit

@main
struct HeartableWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeeklyRecapWidget()
        FriendActivityWidget()
    }
}
