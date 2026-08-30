import SwiftUI

/// Three places, and no fourth.
///
/// Deliberately not a social app: there is no wall to browse and no one to search
/// for. You record, you learn, and you decide who sees what. Discovery is the thing
/// that would turn this into Instagram, so it is left out rather than hidden.
///
/// It opens on the profile because that is your recordings — the reason you came
/// back. Recording is what you do next, not what you are greeted with.
struct MainTabView: View {
    private enum Tab { case record, lessons, profile }

    @State private var tab: Tab = .profile

    var body: some View {
        TabView(selection: $tab) {
            ContentView()
                .tabItem { Label("Record", systemImage: "figure.dance") }
                .tag(Tab.record)

            NavigationStack { LessonsListView() }
                .tabItem { Label("Lessons", systemImage: "graduationcap.fill") }
                .tag(Tab.lessons)

            NavigationStack { PlatformProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(.orange)
    }
}
