import SwiftUI

struct LandingView: View {
    @Binding var showCamera: Bool
    @Binding var selectedMode: DanceMode
    var onSignOut: () -> Void = {}
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL?
    @State private var showVideoProcessing = false
    @State private var showRecordings = false
    @State private var showModeSelection = false
    @State private var showVideoModeSelection = false
    @State private var videoMode: DanceMode = .styling
    @State private var videoImportError = ""
    
    enum DanceMode {
        case styling
        case partner
    }
    
    var body: some View {
        VStack(spacing: 30) {
            HStack {
                Spacer()
                Button("Sign Out", action: onSignOut)
                    .font(.subheadline)
                    .padding(.trailing, 20)
            }

            Spacer()
            
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
            
            Text("Dance Sage")
                .font(.system(size: 36, weight: .bold))
            
            Spacer()
            
            // Live Camera Button
            Button(action: {
                showModeSelection = true
            }) {
                Text("RECORD LIVE")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 250, height: 60)
                    .background(Color.blue)
                    .cornerRadius(30)
            }
            
            // Upload Video Button
            Button(action: {
                showVideoModeSelection = true
            }) {
                Text("UPLOAD VIDEO")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 250, height: 60)
                    .background(Color.green)
                    .cornerRadius(30)
            }
            
            // My Recordings Button
            Button(action: {
                showRecordings = true
            }) {
                Text("MY RECORDINGS")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 250, height: 60)
                    .background(Color.purple)
                    .cornerRadius(30)
            }
            
            Spacer()
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
        .sheet(isPresented: $showVideoProcessing, onDismiss: cleanupSelectedVideo) {
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
