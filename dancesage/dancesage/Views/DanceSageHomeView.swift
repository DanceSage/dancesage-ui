import SwiftUI

struct DanceSageHomeView: View {
    @Binding var showCamera: Bool
    @Binding var selectedMode: LandingView.DanceMode

    private let background = Color(red: 81 / 255, green: 63 / 255, blue: 89 / 255)

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                Circle()
                    .fill(.orange.opacity(0.18))
                    .frame(width: 250, height: 250)
                    .blur(radius: 70)
                    .offset(x: 170, y: -310)
                Circle()
                    .fill(.green.opacity(0.14))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: -170, y: 300)

                ScrollView {
                    VStack(spacing: 22) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 128, height: 128)
                            .accessibilityHidden(true)

                        VStack(spacing: 6) {
                            Text("DanceSage")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                            Text("Find the floor. Refine your dance.")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .foregroundStyle(.white)

                        NavigationLink {
                            DanceDiscoveryView()
                        } label: {
                            HomePathCard(
                                title: "Find a Dance Tonight",
                                subtitle: "Source-backed salsa, bachata and Latin events near you",
                                icon: "location.fill",
                                color: .orange
                            )
                        }

                        NavigationLink {
                            LandingView(showCamera: $showCamera, selectedMode: $selectedMode)
                        } label: {
                            HomePathCard(
                                title: "Practice & Improve",
                                subtitle: "Record, import and review your movement as a skeleton",
                                icon: "figure.dance",
                                color: .green
                            )
                        }

                        NavigationLink {
                            WatchedEventsView()
                        } label: {
                            Label("My watched events", systemImage: "bookmark.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.orange)
    }
}

private struct HomePathCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 56, height: 56)
                .background(color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.subheadline.bold())
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.13)) }
    }
}
