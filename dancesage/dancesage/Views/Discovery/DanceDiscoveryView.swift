import SwiftUI

struct DanceDiscoveryView: View {
    @AppStorage("lastDanceSearchCity") private var city = ""
    @State private var date = Date()
    @State private var styles = Set(DanceStyle.allCases)
    @State private var response: EventSearchResponse?
    @State private var isSearching = false
    @State private var errorMessage = ""
    @FocusState private var cityFocused: Bool

    private let service = DanceEventService()

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.08, blue: 0.12).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Where will you dance?")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text("Fresh results with a source for every event.")
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    VStack(spacing: 16) {
                        Label {
                            TextField("City, e.g. Toronto", text: $city)
                                .textInputAutocapitalization(.words)
                                .focused($cityFocused)
                                .submitLabel(.search)
                                .onSubmit(search)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(.orange)
                        }
                        .padding(15)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))

                        DatePicker("Date", selection: $date, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(.orange)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Styles").font(.subheadline.weight(.semibold))
                            HStack {
                                ForEach(DanceStyle.allCases) { style in
                                    Button {
                                        if styles.contains(style) {
                                            if styles.count > 1 { styles.remove(style) }
                                        } else {
                                            styles.insert(style)
                                        }
                                    } label: {
                                        Text(style.title)
                                            .font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(styles.contains(style) ? Color.orange : .white.opacity(0.08), in: Capsule())
                                    }
                                }
                            }
                        }

                        Button(action: search) {
                            HStack {
                                if isSearching { ProgressView().tint(.black) }
                                Text(isSearching ? "Searching live sources…" : "Find dances")
                                    .font(.headline)
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 15))
                        }
                        .disabled(city.trimmingCharacters(in: .whitespaces).count < 2 || isSearching)
                        .opacity(city.trimmingCharacters(in: .whitespaces).count < 2 ? 0.5 : 1)
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))

                    if let response {
                        EventResultsSection(response: response)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Dance Tonight")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .alert("Search unavailable", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage) }
    }

    private func search() {
        guard !isSearching else { return }
        cityFocused = false
        isSearching = true
        response = nil
        let query = EventSearchQuery(
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            region: nil,
            country: nil,
            date: Self.apiDateFormatter.string(from: date),
            styles: DanceStyle.allCases.filter(styles.contains)
        )
        Task {
            do { response = try await service.search(query) }
            catch { errorMessage = error.localizedDescription }
            isSearching = false
        }
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct EventResultsSection: View {
    let response: EventSearchResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(response.events.isEmpty ? "No verified events found" : "(response.events.count) dances found")
                    .font(.title2.bold())
                Spacer()
                Text("Checked (response.checkedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if response.events.isEmpty {
                Text("Try another date or style. DanceSage only shows results it can tie to a live source for this date.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
            } else {
                ForEach(response.events) { event in EventCard(event: event) }
            }
        }
    }
}

struct EventCard: View {
    let event: DanceEvent
    @EnvironmentObject private var watched: WatchedEventStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.name).font(.headline).foregroundStyle(.white)
                    Text(event.styles.map(\.title).joined(separator: " • "))
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                Spacer()
                Button { watched.toggle(event) } label: {
                    Image(systemName: watched.contains(event) ? "bookmark.fill" : "bookmark")
                        .font(.title3).foregroundStyle(.orange)
                }
                .accessibilityLabel(watched.contains(event) ? "Stop watching event" : "Watch event")
            }
            Label(event.startTime.formatted(date: .abbreviated, time: .shortened), systemImage: "clock.fill")
            Label(event.venueName, systemImage: "building.2.fill")
            if let address = event.address { Label(address, systemImage: "mappin") }
            Text(event.summary).font(.subheadline).foregroundStyle(.white.opacity(0.72))
            Link(destination: event.sourceURL) {
                Label("View source: (event.sourceTitle)", systemImage: "arrow.up.right.square")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            Text("Verify details with the organizer before travelling.")
                .font(.caption2).foregroundStyle(.white.opacity(0.42))
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.82))
        .padding(17)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10)) }
    }
}
