import SwiftUI

/// Post a recording to your Dance Sage profile.
///
/// Private is preselected on purpose: nothing becomes visible to anyone else unless
/// the person deliberately chooses it. Making that the default rather than a setting
/// buried later is the difference between a promise and a checkbox.
struct PublishToProfileView: View {
    let keypoints: [[[CGPoint]]]
    let fps: Double
    let videoURL: URL?
    var suggestedTitle: String = ""

    @StateObject private var publisher = DanceSagePublisher()
    @ObservedObject private var auth = DanceSageAuth.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var note = ""
    @State private var style = "Bachata"
    @State private var level = "All levels"
    @State private var visibility = "private"
    @State private var showSignIn = false

    private let styles = ["Bachata", "Salsa", "Kizomba", "Zouk", "Other"]
    private let levels = ["Beginner", "Intermediate", "Advanced", "All levels"]

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    signedOut
                } else {
                    switch publisher.stage {
                    case .done(_, let visibility): finished(visibility)
                    default: form
                    }
                }
            }
            .navigationTitle("Post to profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(publisher.stage.isBusy)
                }
            }
            .fullScreenCover(isPresented: $showSignIn) { AccountView(mode: .signIn) }
        }
        .onAppear { if title.isEmpty { title = suggestedTitle } }
        .interactiveDismissDisabled(publisher.stage.isBusy)
    }

    // MARK: - States

    private var signedOut: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 46)).foregroundStyle(.orange)
            Text("Sign in to post").font(.title3.bold())
            Text("Your recordings stay on this iPhone until you post one.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Sign in") { showSignIn = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(34)
    }

    private var form: some View {
        Form {
            Section("What is it") {
                TextField("Name this move", text: $title)
                TextField("A note, if it needs one", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                Picker("Style", selection: $style) {
                    ForEach(styles, id: \.self, content: Text.init)
                }
                Picker("Level", selection: $level) {
                    ForEach(levels, id: \.self, content: Text.init)
                }
            }

            Section {
                Picker("Who can see it", selection: $visibility) {
                    Text("Only me").tag("private")
                    Text("People I share with").tag("granted")
                    Text("Everyone").tag("public")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Who can see it")
            } footer: {
                Text(visibilityExplanation)
            }

            Section {
                switch publisher.stage {
                case .compressing:
                    Label("Preparing the video…", systemImage: "wand.and.stars")
                        .foregroundStyle(.secondary)
                case .uploading:
                    HStack { ProgressView(); Text("Posting…").foregroundStyle(.secondary) }
                case .failed(let message):
                    Text(message).font(.footnote).foregroundStyle(.red)
                default:
                    EmptyView()
                }

                Button {
                    Task { await post() }
                } label: {
                    HStack {
                        Spacer()
                        Text(publisher.stage.isBusy ? "Posting…" : "Post").bold()
                        Spacer()
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                          || publisher.stage.isBusy)
            } footer: {
                Text(videoURL == nil
                     ? "Skeleton only — there is no video on this recording."
                     : "The skeleton and the video are both posted. The copy on this "
                       + "iPhone is not changed.")
            }
        }
    }

    private func finished(_ visibility: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52)).foregroundStyle(.green)
            Text("Posted").font(.title3.bold())
            Text(visibility == "public"
                 ? "It is on your profile and anyone can watch it."
                 : visibility == "granted"
                   ? "It is on your profile, visible to people you share it with."
                   : "It is on your profile, visible only to you. You can make it "
                     + "public whenever you like.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding(34)
    }

    private var visibilityExplanation: String {
        switch visibility {
        case "public":  return "Anyone can find and watch this, on the web too."
        case "granted": return "Only people you give access to. You can take it back later."
        default:        return "Nobody but you. This is the default, and you can change it any time."
        }
    }

    private func post() async {
        await publisher.publish(
            title: title.trimmingCharacters(in: .whitespaces),
            note: note, style: style, level: level, visibility: visibility,
            keypoints: keypoints, fps: fps, videoURL: videoURL)
    }
}
