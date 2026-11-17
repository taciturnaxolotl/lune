import SwiftUI
import SwiftData

@main
struct LuneApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserView()
                .modelContainer(for: [TabRecord.self, HistoryEntry.self, Favorite.self])
        }
    }
}
