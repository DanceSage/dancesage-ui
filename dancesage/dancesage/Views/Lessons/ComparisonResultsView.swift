import SwiftUI

/// The verdict: an overall score, per-region breakdown, and the spoken cues.
struct ComparisonResultsView: View {
    let result: LessonComparator.Result
    let lessonName: String
    let attemptName: String

    @Environment(\.dismiss) private var dismiss

    private var scoreColor: Color {
        switch result.overallScore {
        case 80...: return .green
        case 55..<80: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(spacing: 10) {
                        Text("\(result.overallScore)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor)
                        Text("\(attemptName) vs \(lessonName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Label(
                                result.alignedByBeats ? "Compared on the beat" : "Compared over time",
                                systemImage: result.alignedByBeats ? "metronome" : "clock"
                            )
                            if result.mirrored {
                                Label("Mirrored view", systemImage: "arrow.left.and.right")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("What to work on") {
                    ForEach(Array(result.cues.enumerated()), id: \.offset) { _, cue in
                        Label(cue, systemImage: "speaker.wave.2.fill")
                            .font(.body)
                    }
                    Button {
                        CoachVoice.shared.speak(score: result.overallScore, cues: result.cues)
                    } label: {
                        Label("Say It Again", systemImage: "arrow.clockwise")
                    }
                }

                Section("By body region") {
                    ForEach(result.regions) { region in
                        HStack {
                            Text(region.region.rawValue)
                            Spacer()
                            if let count = region.worstCount, region.meanDeviation > 12 {
                                Text("count \(count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("\(region.score)")
                                .font(.headline.monospacedDigit())
                                .foregroundColor(region.score >= 80 ? .green : (region.score >= 55 ? .yellow : .orange))
                        }
                    }
                }

                Section {
                    Text("Based on \(result.samplesCompared) compared moments. Angles the camera couldn't see were skipped, never judged.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Your Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        CoachVoice.shared.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                CoachVoice.shared.speak(score: result.overallScore, cues: result.cues)
            }
            .onDisappear {
                CoachVoice.shared.stop()
            }
        }
    }
}
