import SwiftUI

/// Posting a recording. One screen, because there was never more than one decision:
/// who gets to see it.
///
/// This replaces two screens that both uploaded and differed only in whether you
/// set a visibility or typed a handle — which meant three routes to the same act
/// and no way to tell them apart from the outside.
struct PostRecordingView: View {
    let keypoints: [[[CGPoint]]]
    var world: [[[PosePoint3D]]] = []
    var frameTimes: [Double] = []
    let fps: Double
    let videoURL: URL?
    var suggestedTitle: String = ""
    /// Told the id once the post exists, so the caller can link the two.
    var onPosted: (Int) -> Void = { _ in }

    @StateObject private var publisher = DanceSagePublisher()
    @Environment(\.dismiss) private var dismiss

    private enum Who: String, CaseIterable, Identifiable {
        case onlyMe = "Only me"
        case people = "People I choose"
        case everyone = "Everyone"
        var id: String { rawValue }

        var visibility: String {
            switch self {
            case .onlyMe:   return "private"
            case .people:   return "granted"
            case .everyone: return "public"
            }
        }
        var footnote: String {
            switch self {
            case .onlyMe:   return "Nobody but you. You can change this later."
            case .people:   return "Only the handles you add. You can take access back at any time."
            case .everyone: return "Anyone can find and watch this, on the web too."
            }
        }
    }

    @State private var title = ""
    @State private var who: Who = .onlyMe
    @State private var handles: [String] = []
    @State private var typing = ""
    @State private var busy = false
    @State private var error: String?
    @State private var posted = false

    private var canPost: Bool {
        !busy && !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (who != .people || !handles.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Group { posted ? AnyView(done) : AnyView(form) }
                .navigationTitle("Post")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(posted ? "Done" : "Cancel") { dismiss() }.disabled(busy)
                    }
                }
        }
        .onAppear { if title.isEmpty { title = suggestedTitle } }
        .interactiveDismissDisabled(busy)
    }

    private var form: some View {
        Form {
            Section {
                TextField("Name this move", text: $title)
            } footer: {
                Text(videoURL == nil
                     ? "The skeleton is uploaded. There is no video on this recording."
                     : "The video and the skeleton are uploaded. The copy on this iPhone does not change.")
            }

            Section {
                Picker("Who can see it", selection: $who) {
                    ForEach(Who.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Who can see it")
            } footer: {
                Text(who.footnote)
            }

            // Recipients live inside the choice that needs them, rather than being
            // a separate screen you have to remember to visit afterwards.
            if who == .people {
                Section("Add people") {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("their handle", text: $typing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addHandle)
                        Button("Add", action: addHandle)
                            .font(.subheadline.weight(.semibold))
                            .disabled(typing.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(handles, id: \.self) { h in
                        HStack {
                            Label("@\(h)", systemImage: "person.fill")
                            Spacer()
                            Button {
                                handles.removeAll { $0 == h }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }
            }

            Section {
                Button {
                    Task { await post() }
                } label: {
                    HStack {
                        Spacer()
                        if busy { ProgressView() } else { Text(label).bold() }
                        Spacer()
                    }
                }
                .disabled(!canPost)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52)).foregroundStyle(.green)
            Text("Posted").font(.title3.bold())
            Text(summary)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding(34)
    }

    private var label: String {
        switch publisher.stage {
        case .compressing: return "Preparing…"
        case .uploading:   return "Posting…"
        default:           return who == .people && !handles.isEmpty
                                  ? "Post and share" : "Post"
        }
    }

    private var summary: String {
        switch who {
        case .onlyMe:   return "It is on your profile, visible only to you."
        case .people:   return "Shared with " + handles.map { "@\($0)" }
                                  .formatted(.list(type: .and)) + "."
        case .everyone: return "It is on your profile and anyone can watch it."
        }
    }

    private func addHandle() {
        let h = typing.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "@", with: "").lowercased()
        guard !h.isEmpty, !handles.contains(h) else { typing = ""; return }
        handles.append(h)
        typing = ""
    }

    private func post() async {
        busy = true; error = nil
        await publisher.publish(title: title.trimmingCharacters(in: .whitespaces),
                                visibility: who.visibility,
                                keypoints: keypoints, world: world,
                                frameTimes: frameTimes, fps: fps, videoURL: videoURL)
        if case .failed(let message) = publisher.stage {
            error = message; busy = false; return
        }
        // Granting after the upload, because a grant needs something to point at.
        if who == .people, let id = publisher.lastPublishedID {
            var failed: [String] = []
            for h in handles {
                do { try await DanceSagePlatform.shared.grant(handle: h, videoID: id) }
                catch { failed.append(h) }
            }
            if !failed.isEmpty {
                error = "Posted, but could not share with "
                    + failed.map { "@\($0)" }.formatted(.list(type: .and))
                    + ". Check the handles and add them from your profile."
                busy = false
                return
            }
        }
        if let id = publisher.lastPublishedID { onPosted(id) }
        posted = true
        busy = false
    }
}
