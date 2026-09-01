import SwiftUI

/// One clip on a wall. Used by the feed, by search, and by what people shared with
/// you — three surfaces, one card, so they cannot drift apart.
struct FeedCard: View {
    let video: FeedVideo
    var showByline: Bool = true
    let onOpen: () -> Void

    @State private var track: SkeletonTrack?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.black.opacity(0.28)
                if let track {
                    SkeletonTrackView(track: track, still: true, lineWidth: 2)
                } else {
                    Image(systemName: "figure.dance")
                        .font(.system(size: 24)).foregroundStyle(.white.opacity(0.2))
                }
            }
            .frame(height: 160)
            .overlay(alignment: .bottomTrailing) {
                Text(video.duration)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(7)
            }
            .overlay(alignment: .topLeading) {
                if video.visibility != "public" {
                    Label(video.visibility == "granted" ? "Shared" : "Private",
                          systemImage: video.visibility == "granted"
                                       ? "person.2.fill" : "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(7)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(video.style + (video.dancers > 1 ? " · partner" : ""))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))

                if showByline {
                    // The move belongs to whoever danced it, so the name rides along.
                    HStack(spacing: 6) {
                        AvatarDot(handle: video.by.handle,
                                  avatar: video.by.avatar,
                                  name: video.by.display_name,
                                  size: 18)
                        Text(video.by.display_name)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(1)
                    }
                    .padding(.top, 3)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onOpen)
        .task(id: video.pose_key) { track = await SkeletonTrack.load(key: video.pose_key) }
    }
}

/// A small round avatar, falling back to an initial when there is no photo.
struct AvatarDot: View {
    let handle: String
    let avatar: String
    let name: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if !avatar.isEmpty, let base = AppConfig.platformBaseURL,
               let url = URL(string: base.absoluteString.trimmingCharacters(
                                in: CharacterSet(charactersIn: "/")) + avatar) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else { placeholder }
                }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle().fill(.white.opacity(0.14))
            .overlay {
                Text(String((name.isEmpty ? handle : name).prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.orange)
            }
    }
}
