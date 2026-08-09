import SwiftUI

@main
struct dancesageApp: App {
    @StateObject private var watchedEvents = WatchedEventStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchedEvents)
        }
    }
}
