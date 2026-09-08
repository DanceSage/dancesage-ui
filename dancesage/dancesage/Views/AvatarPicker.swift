import SwiftUI
import PhotosUI

/// Your picture: tap to pick one from Photos, it is squared, shrunk and sent
/// to the platform, and the circle shows it from then on. Used on sign-up and
/// on the profile.
struct AvatarPicker: View {
    var currentURL: URL?
    var initials: String
    var size: CGFloat = 76
    var onUploaded: () -> Void = {}

    @State private var pick: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var uploading = false
    @State private var error: String?

    var body: some View {
        PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                circle
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay { Circle().stroke(.white.opacity(0.16)) }
                Image(systemName: "camera.fill")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(size * 0.08)
                    .background(.orange, in: Circle())
                    .offset(x: 2, y: 2)
                if uploading {
                    Circle().fill(.black.opacity(0.45)).frame(width: size, height: size)
                    ProgressView().tint(.white).frame(width: size, height: size)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(uploading)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
        .alert("Could Not Set Photo", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder
    private var circle: some View {
        if let preview {
            Image(uiImage: preview).resizable().scaledToFill()
        } else if let currentURL {
            AsyncImage(url: currentURL) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { placeholder }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle().fill(.white.opacity(0.12))
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.orange)
            }
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false; pick = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            error = "That picture could not be read."; return
        }
        let squared = Self.square(image, side: 512)
        guard let jpeg = squared.jpegData(compressionQuality: 0.85) else {
            error = "That picture could not be prepared."; return
        }
        do {
            try await DanceSagePlatform.shared.uploadAvatar(jpeg: jpeg)
            preview = squared
            NotificationCenter.default.post(name: .avatarChanged, object: nil)
            onUploaded()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Centre-cropped to a square and scaled down; a profile picture, not a photo library.
    static func square(_ image: UIImage, side: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let edge = min(w, h)
        let crop = CGRect(x: (w - edge) / 2, y: (h - edge) / 2, width: edge, height: edge)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            let scale = side / edge
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale, width: w * scale, height: h * scale))
        }
    }
}
