import SwiftUI

/// The error-over-time strip under the replay scrubber: a filled trace, green
/// where the student matched and red where they drifted, with markers on the
/// worst moments. Drag anywhere to seek; lift near a marker to snap to it.
///
/// The trace is drawn in a Canvas whose only input is the timeline, so it is
/// rasterised once. The playhead is a separate view offset by time — putting
/// it inside the Canvas would redraw the whole strip sixty times a second.
struct ErrorTimelineStrip: View {
    let timeline: AttemptTimeline
    let currentTime: Double
    let onSeek: (Double) -> Void
    let onPeakTap: (AttemptTimeline.Peak) -> Void

    private let height: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))

                trace
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                ForEach(timeline.peaks) { peak in
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .offset(x: x(for: peak.time, width: width) - 4.5, y: -height / 2 + 5)
                }

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .offset(x: x(for: currentTime, width: width) - 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(time(forX: value.location.x, width: width))
                    }
                    .onEnded { value in
                        let seconds = time(forX: value.location.x, width: width)
                        if let peak = timeline.nearestPeak(to: seconds) {
                            onPeakTap(peak)
                        } else {
                            onSeek(seconds)
                        }
                    }
            )
        }
        .frame(height: height)
        .accessibilityLabel("Error timeline")
        .accessibilityValue(accessibilityDescription)
    }

    private var trace: some View {
        Canvas { context, size in
            let errors = timeline.errors
            guard errors.count > 1 else { return }
            let columnWidth = size.width / CGFloat(errors.count - 1)

            for (index, value) in errors.enumerated() {
                guard let value else { continue }
                let level = min(1, max(0, value))
                let barHeight = max(2, CGFloat(level) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * columnWidth - columnWidth / 2,
                    y: size.height - barHeight,
                    width: columnWidth + 0.5,
                    height: barHeight
                )
                context.fill(Path(rect), with: .color(color(for: level)))
            }
        }
    }

    /// Same ramp SkeletonOverlay grades joints with, so strip and skeleton agree.
    private func color(for level: Double) -> Color {
        Color(red: min(1, level * 2), green: min(1, (1 - level) * 2), blue: 0.12).opacity(0.85)
    }

    private func x(for seconds: Double, width: CGFloat) -> CGFloat {
        guard timeline.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, seconds / timeline.duration))) * width
    }

    private func time(forX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(1, max(0, x / width))) * timeline.duration
    }

    private var accessibilityDescription: String {
        guard let worst = timeline.worstPeak else { return "No clear problem moments." }
        let count = worst.count.map { ", count \($0)" } ?? ""
        return "\(timeline.peaks.count) problem moments. Worst at \(Int(worst.time)) seconds\(count)."
    }
}
