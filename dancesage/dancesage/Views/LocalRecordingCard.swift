import SwiftUI

/// A recording that is on this iPhone and nowhere else.
///
/// It sits on the profile beside the posted ones because to the person holding the
/// phone they are the same thing — their dancing. The only difference is who else
/// can see it, which is what the badge says.
struct LocalRecordingCard: View {
    let recording: DanceRecording
    let onOpen: () -> Void
    let onPost: () -> Void
    let onDelete: () -> Void

    private var seconds: Int {
        let fps = recording.fps ?? 15
        return fps > 0 ? Int(Double(recording.frameCount) / fps) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tapping the picture or the title plays it. Post sits outside that
            // button — a tap target over the whole card would swallow it.
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        Color.black.opacity(0.28)
                        LocalSkeletonPreview(keypoints: recording.keypoints,
                                             fps: recording.fps ?? 15,
                                             isPartner: recording.mode == .partner)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .overlay(alignment: .bottomTrailing) {
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(7)
                    }
                    .overlay(alignment: .topLeading) {
                        Label("On this iPhone", systemImage: "iphone")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding(7)
                    }

                    Text(recording.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.top, 11)
                }
            }
            .buttonStyle(.plain)

            HStack {
                Button(action: onPost) {
                    Label("Post", systemImage: "arrow.up.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.orange.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.top, 7)
            .padding(.bottom, 11)
        }
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contextMenu {
            Button("Post…", systemImage: "arrow.up.circle", action: onPost)
            Divider()
            Button("Delete recording", systemImage: "trash",
                   role: .destructive, action: onDelete)
        }
    }
}

/// Plays a local recording's keypoints. The posted cards fetch a track from the
/// server; this one already has the points in memory.
struct LocalSkeletonPreview: View {
    let keypoints: [[[CGPoint]]]
    let fps: Double
    let isPartner: Bool
    /// Still by default, for the same reason the posted cards are.
    var still: Bool = true

    private var bones: [[Int]] {
        // Vision gives 17 joints in partner mode, MediaPipe 33 in styling.
        (keypoints.first?.first?.count ?? 33) == 17
            ? SkeletonTrack.bones17 : SkeletonTrack.bones33
    }

    var body: some View {
        TimelineView(.animation(paused: still)) { timeline in
            Canvas { context, size in
                guard !keypoints.isEmpty else { return }
                let rate = fps > 0 ? fps : 15
                let f = still
                    ? keypoints.count / 3
                    : Int(timeline.date.timeIntervalSinceReferenceDate * rate) % keypoints.count
                let frame = keypoints[f]

                for (which, person) in frame.enumerated() {
                    guard !person.isEmpty else { continue }
                    let points = person.map {
                        CGPoint(x: $0.x * size.width, y: $0.y * size.height)
                    }
                    var path = Path()
                    for bone in bones where bone[0] < points.count && bone[1] < points.count {
                        path.move(to: points[bone[0]])
                        path.addLine(to: points[bone[1]])
                    }
                    let colour = SkeletonTrack.colours[which % SkeletonTrack.colours.count]
                    context.stroke(path, with: .color(colour.opacity(0.22)),
                                   style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    context.stroke(path, with: .color(colour),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                      lineJoin: .round))
                    for point in points {
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 1.4, y: point.y - 1.4,
                                                            width: 2.8, height: 2.8)),
                                     with: .color(SkeletonTrack.jointColour))
                    }
                }
            }
        }
    }
}
