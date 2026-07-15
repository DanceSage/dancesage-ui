import SwiftUI

struct LandingView: View {
    @Binding var showCamera: Bool
    @Binding var selectedMode: DanceMode
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL?
    @State private var showVideoProcessing = false
    @State private var showRecordings = false
    @State private var showModeSelection = false
    @State private var showVideoModeSelection = false
    @State private var videoMode: DanceMode = .styling
    @State private var videoImportError = ""

    // Matches the outer pixels of AppLogo so the JPEG blends into the page.
    private let logoBackground = Color(
        red: 81.0 / 255.0,
        green: 63.0 / 255.0,
        blue: 89.0 / 255.0
    )
    
    enum DanceMode {
        case styling
        case partner
    }
    
    var body: some View {
        ZStack {
            logoBackground
                .ignoresSafeArea()

            // Soft glows borrow the jewel colors from the logo without competing with it.
            Circle()
                .fill(Color.green.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 55)
                .offset(x: -175, y: -330)

            Circle()
                .fill(Color.orange.opacity(0.15))
                .frame(width: 210, height: 210)
                .blur(radius: 60)
                .offset(x: 175, y: -235)

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)

                Text("DanceSage")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("See the movement. Refine the style.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .padding(.top, 7)

                Spacer(minLength: 30)

                VStack(spacing: 14) {
                    Button {
                        showModeSelection = true
                    } label: {
                        LandingActionLabel(
                            title: "Record Live",
                            subtitle: "Use the front or back camera",
                            icon: "camera.fill",
                            accent: .orange
                        )
                    }

                    Button {
                        showVideoModeSelection = true
                    } label: {
                        LandingActionLabel(
                            title: "Upload Video",
                            subtitle: "Analyze a video from your phone",
                            icon: "play.rectangle.fill",
                            accent: .green
                        )
                    }

                    Button {
                        showRecordings = true
                    } label: {
                        LandingActionLabel(
                            title: "My Recordings",
                            subtitle: "Return to your saved sessions",
                            icon: "square.stack.fill",
                            accent: .purple
                        )
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 22)

                Label("Private • Processed on this iPhone", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showModeSelection) {
            ModeSelectionView(
                selectedMode: $selectedMode,
                onModeSelected: {
                    showModeSelection = false
                    showCamera = true
                }
            )
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker(selectedVideoURL: $selectedVideoURL, errorMessage: $videoImportError)
        }
        .fullScreenCover(isPresented: $showVideoProcessing, onDismiss: cleanupSelectedVideo) {
            if let url = selectedVideoURL {
                VideoProcessingView(videoURL: url, isPartnerMode: videoMode == .partner)
            }
        }
        .sheet(isPresented: $showRecordings) {
            RecordingsListView()
        }
        .sheet(isPresented: $showVideoModeSelection) {
            VideoModeSelectionView(
                selectedMode: $videoMode,
                onModeSelected: {
                    showVideoModeSelection = false
                    showVideoPicker = true
                }
            )
        }
        .onChange(of: selectedVideoURL) { oldValue, newValue in
            if newValue != nil {
                showVideoProcessing = true
            }
        }
        .alert("Video Import Failed", isPresented: Binding(
            get: { !videoImportError.isEmpty },
            set: { if !$0 { videoImportError = "" } }
        )) {
            Button("OK", role: .cancel) { videoImportError = "" }
        } message: {
            Text(videoImportError)
        }
    }

    private func cleanupSelectedVideo() {
        guard let selectedVideoURL else { return }
        try? FileManager.default.removeItem(at: selectedVideoURL)
        self.selectedVideoURL = nil
    }
}

private struct LandingActionLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 46, height: 46)
                .background(accent.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.62))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
    }
}

// MARK: - Video Mode Selection View
struct VideoModeSelectionView: View {
    @Binding var selectedMode: LandingView.DanceMode
    let onModeSelected: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 40) {
            Text("What's in this video?")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 50)
            
            Text("Choose the analysis mode")
                .font(.system(size: 16))
                .foregroundColor(.gray)
            
            Spacer()
            
            // Styling Mode
            Button(action: {
                selectedMode = .styling
                onModeSelected()
            }) {
                VStack(spacing: 15) {
                    Image(systemName: "figure.dance")
                        .font(.system(size: 60))
                    Text("STYLING")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Solo dancer / Footwork")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                }
                .foregroundColor(.white)
                .frame(width: 280, height: 200)
                .background(Color.green)
                .cornerRadius(20)
            }
            
            // Partner Mode — experimental warning
            Button(action: {
                selectedMode = .partner
                onModeSelected()
            }) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 15) {
                        HStack(spacing: 10) {
                            Image(systemName: "figure.dance")
                                .font(.system(size: 50))
                                .foregroundColor(.green)
                            Image(systemName: "figure.dance")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                        }
                        Text("PARTNER")
                            .font(.system(size: 24, weight: .semibold))
                        Text("Two dancers together")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .foregroundColor(.white)
                    .frame(width: 280, height: 200)
                    .background(Color.blue)
                    .cornerRadius(20)
                    
                    // Experimental badge
                    Text("EXPERIMENTAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(10)
                        .padding(8)
                }
            }
            
            // Partner mode disclaimer
            Text("⚠️ Partner pose detection is experimental. Skeletons may jump when bodies overlap. Full refinement coming in version 2.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Cancel")
                    .font(.system(size: 18))
                    .foregroundColor(.red)
            }
            .padding(.bottom, 30)
        }
    }
}

// MARK: - Live Mode Selection View
struct ModeSelectionView: View {
    @Binding var selectedMode: LandingView.DanceMode
    let onModeSelected: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Select Mode")
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 50)
            
            Spacer()
            
            // Styling Mode
            Button(action: {
                selectedMode = .styling
                onModeSelected()
            }) {
                VStack(spacing: 15) {
                    Image(systemName: "figure.dance")
                        .font(.system(size: 60))
                    Text("STYLING")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Single dancer")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .foregroundColor(.white)
                .frame(width: 280, height: 200)
                .background(Color.green)
                .cornerRadius(20)
            }
            
            // Partner Mode — experimental
            Button(action: {
                selectedMode = .partner
                onModeSelected()
            }) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 15) {
                        HStack(spacing: 10) {
                            Image(systemName: "figure.dance")
                                .font(.system(size: 50))
                            Image(systemName: "figure.dance")
                                .font(.system(size: 50))
                        }
                        Text("PARTNER")
                            .font(.system(size: 24, weight: .semibold))
                        Text("Two dancers")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    .foregroundColor(.white)
                    .frame(width: 280, height: 200)
                    .background(Color.blue)
                    .cornerRadius(20)
                    
                    // Experimental badge
                    Text("EXPERIMENTAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(10)
                        .padding(8)
                }
            }
            
            Text("⚠️ Partner detection is experimental. Skeletons may jump when bodies overlap.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Cancel")
                    .font(.system(size: 18))
                    .foregroundColor(.red)
            }
            .padding(.bottom, 30)
        }
    }
}
