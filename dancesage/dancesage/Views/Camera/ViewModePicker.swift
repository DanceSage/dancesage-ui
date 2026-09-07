import SwiftUI

/// What a player shows: the video, the skeleton, or both on top of each other.
///
/// One control for every player — the recording playback, a post, the web —
/// in one order, so switching views feels the same wherever a clip is opened.
enum ViewMode: String, CaseIterable, Identifiable {
    case both = "Both"
    case video = "Video"
    case skeleton = "Skeleton"

    var id: Self { self }
    var showsVideo: Bool { self != .skeleton }
    var showsSkeleton: Bool { self != .video }
}

struct ViewModePicker: View {
    @Binding var mode: ViewMode

    var body: some View {
        Picker("Show", selection: $mode) {
            ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .colorScheme(.dark)
    }
}

/// Switches for each skeleton in a multi-dancer track: see one, the other, or
/// both. Colours match the renderer's per-dancer palette.
struct DancerToggles: View {
    let labels: [String]
    let colors: [Color]
    @Binding var hidden: Set<Int>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(labels.indices, id: \.self) { index in
                let isOn = !hidden.contains(index)
                let color = colors[index % max(colors.count, 1)]
                Button {
                    if isOn { hidden.insert(index) } else { hidden.remove(index) }
                } label: {
                    Label(labels[index], systemImage: isOn ? "circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isOn ? color : .white.opacity(0.45))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isOn ? color.opacity(0.18) : Color.clear, in: Capsule())
                }
                .accessibilityLabel("\(labels[index]) skeleton")
                .accessibilityValue(isOn ? "shown" : "hidden")
            }
        }
    }
}
