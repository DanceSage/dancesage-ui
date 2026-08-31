import SwiftUI

/// A loaded pose track, ready to draw.
///
/// The projection deliberately mirrors `static/skeleton.js` on the web — same centring,
/// same 1.45 scale factor, same yaw. Two implementations of "what does this dancer look
/// like" that disagree is exactly the bug that made the app and the site look unrelated.
struct SkeletonTrack {
    let dancers: [[[[Double]]]]      // [dancer][frame][joint][xyz]
    let bones: [[Int]]
    let frames: Int
    let fps: Double
    let is2d: Bool
    /// True only when depth actually varies. A track uploaded from the phone carries
    /// three numbers per joint but zero depth, and turning that would just squash the
    /// dancer flat — so the renderer checks rather than trusting the dimension count.
    let hasDepth: Bool
    /// 3D only: the centre of the whole track and its largest span, measured once.
    let centre: (x: Double, y: Double, z: Double)
    let span: Double

    var duration: Double { fps > 0 ? Double(frames) / fps : 0 }

    static let bones33 = [[0,2],[0,5],[2,7],[5,8],[9,10],
        [11,12],[11,13],[13,15],[12,14],[14,16],
        [15,17],[15,19],[15,21],[17,19],[16,18],[16,20],[16,22],[18,20],
        [11,23],[12,24],[23,24],[23,25],[25,27],[24,26],[26,28],
        [27,29],[27,31],[29,31],[28,30],[28,32],[30,32]]
    static let bones17 = [[0,1],[0,2],[1,3],[2,4],[5,6],[5,7],[7,9],[6,8],[8,10],
        [5,11],[6,12],[11,12],[11,13],[13,15],[12,14],[14,16]]

    /// `DANCER` in skeleton.js.
    static let colours = [
        Color(red: 0.227, green: 0.839, blue: 0.690),   // #3ad6b0
        Color(red: 1.000, green: 0.561, blue: 0.639)    // #ff8fa3
    ]
    static let jointColour = Color(red: 1.0, green: 0.902, blue: 0.639)  // #ffe6a3

    static func load(key: String) async -> SkeletonTrack? {
        guard !key.isEmpty,
              let raw = try? await DanceSagePlatform.shared.poseTrack(key: key),
              let first = raw.j.first, !first.isEmpty else { return nil }

        var lo = [Double.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude]
        var hi = [-Double.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        for dancer in raw.j {
            for frame in dancer {
                for joint in frame {
                    for k in 0..<min(3, joint.count) {
                        lo[k] = min(lo[k], joint[k]); hi[k] = max(hi[k], joint[k])
                    }
                }
            }
        }
        guard lo[0] < hi[0] else { return nil }
        let is2d = (first.first?.first?.count ?? 3) == 2
        let depth = is2d ? 0 : (hi[2] - lo[2])
        // A hair of tolerance: floating point noise is not depth.
        let hasDepth = depth > 0.01
        let span = max(hi[0] - lo[0], max(hi[1] - lo[1], depth))

        return SkeletonTrack(
            dancers: raw.j,
            bones: (first.first?.count ?? 33) == 17 ? bones17 : bones33,
            frames: raw.j.map(\.count).min() ?? first.count,
            fps: raw.fps > 0 ? Double(raw.fps) : 30,
            is2d: is2d,
            hasDepth: hasDepth,
            centre: ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2,
                     is2d ? 0 : (lo[2] + hi[2]) / 2),
            span: max(span, 0.0001))
    }
}

/// Draws a pose track.
///
/// Give it a `time` to follow something else — the video, a scrubber — or leave it nil
/// and it runs on its own clock. `yaw` turns a 3D track, which is what the web's Turn
/// slider does; a 2D track ignores it, having no depth to turn.
struct SkeletonTrackView: View {
    let track: SkeletonTrack
    var time: Double? = nil
    var yaw: Double = 0.3
    var lineWidth: CGFloat = 3
    var glow: Bool = true

    var body: some View {
        TimelineView(.animation(paused: time != nil)) { timeline in
            Canvas { context, size in
                draw(at: position(for: timeline.date), in: context, size: size)
            }
        }
    }

    /// Fractional, so frames are interpolated rather than stepped — the web does the
    /// same, and it is the difference between fluid and juddery at low frame rates.
    private func position(for date: Date) -> Double {
        guard track.frames > 0 else { return 0 }
        if let time { return min(Double(track.frames - 1), max(0, time * track.fps)) }
        return (date.timeIntervalSinceReferenceDate * track.fps)
            .truncatingRemainder(dividingBy: Double(track.frames))
    }

    private func pose(_ dancer: [[[Double]]], at f: Double) -> [[Double]] {
        let n = dancer.count
        guard n > 0 else { return [] }
        let i = Int(f) % n, k = (i + 1) % n, u = f - f.rounded(.down)
        return zip(dancer[i], dancer[k]).map { a, c in
            (0..<a.count).map { a[$0] + (c[$0] - a[$0]) * u }
        }
    }

    private func draw(at f: Double, in context: GraphicsContext, size: CGSize) {
        for (which, dancer) in track.dancers.enumerated() {
            let joints = pose(dancer, at: f)
            guard !joints.isEmpty else { continue }
            let points = joints.map { project($0, in: size) }

            var path = Path()
            for bone in track.bones where bone[0] < points.count && bone[1] < points.count {
                path.move(to: points[bone[0]])
                path.addLine(to: points[bone[1]])
            }
            let colour = SkeletonTrack.colours[which % SkeletonTrack.colours.count]
            // The soft wide pass under the solid one, as on the web.
            if glow {
                context.stroke(path, with: .color(colour.opacity(0.22)),
                               style: StrokeStyle(lineWidth: lineWidth * 3,
                                                  lineCap: .round, lineJoin: .round))
            }
            context.stroke(path, with: .color(colour),
                           style: StrokeStyle(lineWidth: lineWidth,
                                              lineCap: .round, lineJoin: .round))
            let r = lineWidth * 0.62
            for point in points {
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(SkeletonTrack.jointColour))
            }
        }
    }

    /// `project()` in skeleton.js, line for line.
    private func project(_ q: [Double], in size: CGSize) -> CGPoint {
        if track.is2d {
            return CGPoint(x: q[0] * size.width, y: q[1] * size.height)
        }
        // A track with no depth came from a phone camera, where y grows downward;
        // a fitted 3D track is metres with y up. Flipping the first puts the dancer
        // on their head, so which way is up is read from the data, not assumed.
        if !track.hasDepth {
            let sc = min(size.width, size.height) / (track.span * 1.45)
            return CGPoint(x: size.width / 2 + (q[0] - track.centre.x) * sc,
                           y: size.height / 2 + (q[1] - track.centre.y) * sc)
        }
        let cy = cos(yaw), sy = sin(yaw)
        let x = q[0] - track.centre.x
        let y = q[1] - track.centre.y
        let z = (q.count > 2 ? q[2] : 0) - track.centre.z
        let sc = min(size.width, size.height) / (track.span * 1.45)
        return CGPoint(x: size.width / 2 + (x * cy + z * sy) * sc,
                       y: size.height / 2 - y * sc)
    }
}
