import SwiftUI

/// Share one recording with one person, by handle.
///
/// This replaces sending a `.dancesage` file. The difference is not convenience —
/// a file, once sent, is theirs forever and there is nothing you can do about it.
/// Access is a record, so you can take it back.
///
/// Sharing has to upload first: you cannot grant access to something that only
/// exists on this iPhone. That happens here rather than being a step to remember.
struct ShareWithPersonView: View {
    let keypoints: [[[CGPoint]]]
    let fps: Double
    let videoURL: URL?
    var suggestedTitle: String = ""
    /// Already posted? Then there is nothing to upload, only someone to add.
    var existingVideoID: Int? = nil

    @StateObject private var publisher = DanceSagePublisher()
    @Environment(\.dismiss) private var dismiss

    @State private var handle = ""
    @State private var title = ""
    @State private var busy = false
    @State private var error: String?
    @State private var doneWith: String?

    private var needsUpload: Bool { existingVideoID == nil }

    private var canSend: Bool {
        !busy && !handle.trimmingCharacters(in: .whitespaces).isEmpty
            && (!needsUpload || !title.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let doneWith {
                    Section {
                        Label("Shared with @\(doneWith)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("They can watch it whenever they like. Remove them from "
                             + "your profile and it stops working.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        HStack(spacing: 2) {
                            Text("@").foregroundStyle(.secondary)
                            TextField("their handle", text: $handle)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        Text("Share with")
                    } footer: {
                        Text("They need a Dance Sage account. Only this recording "
                             + "becomes visible to them — nothing else.")
                    }

                    if needsUpload {
                        Section {
                            TextField("Name this move", text: $title)
                        } footer: {
                            Text(videoURL == nil
                                 ? "The skeleton is uploaded so they can watch it."
                                 : "The video and the skeleton are uploaded so they can watch it.")
                        }
                    }

                    if let error {
                        Section { Text(error).font(.footnote).foregroundStyle(.red) }
                    }

                    Section {
                        Button {
                            Task { await share() }
                        } label: {
                            HStack {
                                Spacer()
                                if busy { ProgressView() }
                                else { Text(stageLabel).bold() }
                                Spacer()
                            }
                        }
                        .disabled(!canSend)
                    }
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(doneWith == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(busy)
                }
            }
        }
        .onAppear { if title.isEmpty { title = suggestedTitle } }
        .interactiveDismissDisabled(busy)
    }

    private var stageLabel: String {
        switch publisher.stage {
        case .compressing: return "Preparing…"
        case .uploading:   return "Uploading…"
        default:           return "Share"
        }
    }

    private func share() async {
        busy = true; error = nil
        let who = handle.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "@", with: "").lowercased()

        var videoID = existingVideoID
        if videoID == nil {
            // Shared, not public — it is going to one person, not the world.
            await publisher.publish(title: title.trimmingCharacters(in: .whitespaces),
                                    visibility: "granted",
                                    keypoints: keypoints, fps: fps, videoURL: videoURL)
            if case .failed(let message) = publisher.stage {
                error = message; busy = false; return
            }
            videoID = publisher.lastPublishedID
        }

        guard let videoID else {
            error = "Could not upload the recording."; busy = false; return
        }
        do {
            try await DanceSagePlatform.shared.grant(handle: who, videoID: videoID)
            doneWith = who
        } catch {
            // The upload worked even if the handle did not, so say so.
            self.error = error.localizedDescription
                + (existingVideoID == nil ? " The recording was posted as Shared." : "")
        }
        busy = false
    }
}
