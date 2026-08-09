import SwiftUI

struct WatchedEventsView: View {
    @EnvironmentObject private var watched: WatchedEventStore

    var body: some View {
        Group {
            if watched.events.isEmpty {
                ContentUnavailableView(
                    "No watched events",
                    systemImage: "bookmark",
                    description: Text("Bookmark a dance to keep it here and receive a reminder before it starts.")
                )
            } else {
                List {
                    ForEach(watched.events) { event in
                        EventCard(event: event).listRowBackground(Color.clear)
                    }
                    .onDelete(perform: watched.remove)
                }
                .listStyle(.plain)
            }
        }
        .background(Color(red: 0.10, green: 0.08, blue: 0.12).ignoresSafeArea())
        .navigationTitle("Watched Events")
        .preferredColorScheme(.dark)
    }
}
