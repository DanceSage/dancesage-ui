import SwiftUI
import UIKit

/// A video ready to hand to the iOS share sheet.
struct ExportedVideo: Identifiable {
    let id = UUID()
    let url: URL
}

/// Presents the iOS share sheet.
///
/// `ShareLink` is not used for this: inside a `Menu` presented from a `fullScreenCover` it
/// silently fails to appear, and exported videos have to be shared programmatically once the
/// render finishes anyway. Driving every share through one sheet keeps the behaviour identical
/// everywhere.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
