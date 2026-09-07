import SwiftUI

/// The switches over a player's picture. One pill per thing that can be shown
/// — the video, the skeleton, each dancer — lit in its own colour when on.
/// They sit on top of the picture, where there is room; the bottom is for
/// transport. No "both": two pills on means both.

/// A capsule that reads as a switch.
struct LayerPill: View {
    let title: String
    let color: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isOn ? "circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isOn ? color : .white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? color.opacity(0.18) : Color.clear, in: Capsule())
        }
        .accessibilityValue(isOn ? "shown" : "hidden")
    }
}

/// Video and Skeleton, each on or off.
struct LayerToggles: View {
    @Binding var showVideo: Bool
    @Binding var showSkeleton: Bool
    var hasVideo: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if hasVideo {
                LayerPill(title: "Video", color: .white, isOn: showVideo) { showVideo.toggle() }
            }
            LayerPill(title: "Skeleton", color: Color(red: 0.20, green: 0.95, blue: 0.92), isOn: showSkeleton) { showSkeleton.toggle() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.6), in: Capsule())
    }
}

/// One pill per skeleton in a multi-dancer track, in that skeleton's colour.
struct DancerToggles: View {
    let labels: [String]
    let colors: [Color]
    @Binding var hidden: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(labels.indices, id: \.self) { index in
                let isOn = !hidden.contains(index)
                LayerPill(title: labels[index], color: colors[index % max(colors.count, 1)], isOn: isOn) {
                    if isOn { hidden.insert(index) } else { hidden.remove(index) }
                }
                .accessibilityLabel("\(labels[index]) skeleton")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.6), in: Capsule())
    }
}

/// One speed control for every player: a slider from ¼x to 2x, remembered
/// across players — slow is a habit, not a setting.
struct SpeedSlider: View {
    @Binding var rate: Double

    static func label(_ rate: Double) -> String {
        switch rate {
        case 0.25: return "¼x"
        case 0.5: return "½x"
        case 0.75: return "¾x"
        case 1.25: return "1¼x"
        case 1.5: return "1½x"
        case 1.75: return "1¾x"
        default: return "\(Int(rate))x"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Speed").font(.caption).foregroundStyle(.white.opacity(0.6))
            Slider(value: $rate, in: 0.25...2, step: 0.25).tint(.orange)
        }
    }
}
