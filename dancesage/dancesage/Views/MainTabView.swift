import SwiftUI
import UIKit

/// Four places: record, Sage, lessons, you.
///
/// Deliberately not a social app: there is no wall to browse and no one to search
/// for. You record, you learn, and you decide who sees what. Discovery is the thing
/// that would turn this into Instagram, so it is left out rather than hidden.
///
/// It opens on the profile because that is your recordings — the reason you came
/// back. Recording is what you do next, not what you are greeted with.
struct MainTabView: View {
    private enum Tab { case record, sage, lessons, profile }

    @State private var tab: Tab = .profile
    /// Your picture as the Profile tab's icon, once there is one.
    @State private var tabAvatar: UIImage?
    @ObservedObject private var auth = DanceSageAuth.shared

    var body: some View {
        TabView(selection: $tab) {
            ContentView()
                .tabItem { Label("Record", systemImage: "figure.dance") }
                .tag(Tab.record)

            NavigationStack { SageView() }
                .tabItem { Label("Sage", systemImage: "sparkles") }
                .tag(Tab.sage)

            NavigationStack { LessonsListView() }
                .tabItem { Label("Lessons", systemImage: "graduationcap.fill") }
                .tag(Tab.lessons)

            NavigationStack { PlatformProfileView() }
                .tabItem {
                    if let tabAvatar {
                        Label { Text("Profile") } icon: { Image(uiImage: tabAvatar).renderingMode(.original) }
                    } else {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                }
                .tag(Tab.profile)
        }
        .tint(.orange)
        .task(id: auth.isSignedIn) { await loadTabAvatar() }
        .onReceive(NotificationCenter.default.publisher(for: .avatarChanged)) { _ in
            Task { await loadTabAvatar() }
        }
    }

    private func loadTabAvatar() async {
        guard auth.isSignedIn,
              let me = try? await DanceSagePlatform.shared.me(),
              let url = me.avatarURL(base: AppConfig.platformBaseURL),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { tabAvatar = nil; return }
        tabAvatar = Self.tabIcon(image)
    }

    /// A 26-point circle with a hairline ring, drawn at screen scale, so the
    /// tab bar shows a face rather than a square photo.
    private static func tabIcon(_ image: UIImage) -> UIImage {
        let side: CGFloat = 26
        let format = UIGraphicsImageRendererFormat.default()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        // The tab bar tints anything it thinks is a template, into a flat white
        // disc; the image itself has to say it is a picture.
        return renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            let path = UIBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            path.addClip()
            let w = image.size.width, h = image.size.height, edge = min(w, h)
            let scale = side / edge
            image.draw(in: CGRect(x: -(w - edge) / 2 * scale, y: -(h - edge) / 2 * scale,
                                  width: w * scale, height: h * scale))
            ctx.cgContext.resetClip()
            UIColor.white.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }
}

extension Notification.Name {
    /// Posted after a new profile picture is uploaded, so every place drawing it reloads.
    static let avatarChanged = Notification.Name("ds.avatarChanged")
}
