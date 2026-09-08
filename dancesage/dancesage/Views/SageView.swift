import SwiftUI

/// Sage, the teacher who is always in. Its classes, filed the way it teaches
/// them: one folder per dance, the moves in order. Open a class and it is a
/// post like any other — add it to Lessons, dance it, send the attempt back.
struct SageView: View {
    static let handle = "sage"

    @ObservedObject private var auth = DanceSageAuth.shared
    @State private var page: DancerPage?
    @State private var error: String?
    @State private var opening: FeedVideo?
    @State private var openedFolder: String?
    /// Classes already in Lessons, by the post they came from.
    @State private var inLessons: Set<Int> = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let page {
                        // Folders only. The classes wait inside, on the folder's wall.
                        ForEach(page.folders) { folder in
                            NavigationLink {
                                SageFolderView(folder: folder, teacherName: page.display_name,
                                               inLessons: $inLessons)
                            } label: {
                                folderRow(folder)
                            }
                            .buttonStyle(.plain)
                        }
                        if !page.videos.isEmpty {
                            Text("More")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.leading, 6)
                            ForEach(page.videos) { classRow($0, folder: nil) }
                        }
                        if page.folders.isEmpty && page.videos.isEmpty {
                            Text("No classes yet.")
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 20)
                        }
                    } else if let error {
                        Text(error).foregroundColor(.red.opacity(0.9)).padding(.top, 20)
                    } else {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Sage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.black, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $opening, onDismiss: { loadLessons() }) { v in
            PlatformVideoDetailView(video: v.asPlatformVideo, teacherName: page?.display_name ?? "Sage",
                                    seriesName: openedFolder)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.18))
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.orange)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(page?.display_name ?? "Sage")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                Text(page?.bio ?? "Your teacher, every class from the first basic to the last turn.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(.top, 8)
    }

    private func folderRow(_ folder: DancerPage.Folder) -> some View {
        let done = folder.videos.filter { inLessons.contains($0.id) }.count
        let levels = SageFolderView.levelOrder.filter { level in folder.videos.contains { $0.level == level } }
        return HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.orange)
                .frame(width: 44, height: 44)
                .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(folder.videos.count) classes · \(levels.joined(separator: ", "))"
                     + (done > 0 ? " · \(done) in your lessons" : ""))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func classRow(_ v: FeedVideo, folder: String?) -> some View {
        Button {
            openedFolder = folder
            opening = v
        } label: {
            HStack(spacing: 12) {
                Image(systemName: v.dancers > 1 ? "figure.socialdance" : "figure.dance")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.orange)
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(v.level) · \(v.duration)\(v.dancers > 1 ? " · couple" : "")")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                if inLessons.contains(v.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .accessibilityLabel("In your lessons")
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard auth.isSignedIn else { error = "Sign in to see Sage's classes."; return }
        do {
            page = try await DanceSagePlatform.shared.dancer(handle: Self.handle)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loadLessons()
    }

    private func loadLessons() {
        inLessons = Set(((try? LessonStore.shared.load()) ?? []).compactMap(\.sourceVideoID))
    }
}


/// One folder's wall: its classes in teaching order, sectioned by level.
struct SageFolderView: View {
    static let levelOrder = ["Beginner", "Intermediate", "Advanced", "All levels"]

    let folder: DancerPage.Folder
    let teacherName: String
    @Binding var inLessons: Set<Int>
    @State private var opening: FeedVideo?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections, id: \.level) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.level)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.leading, 6)
                            ForEach(section.videos) { v in
                                Button { opening = v } label: { row(v) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.black, for: .navigationBar)
        .fullScreenCover(item: $opening, onDismiss: {
            inLessons = Set(((try? LessonStore.shared.load()) ?? []).compactMap(\.sourceVideoID))
        }) { v in
            PlatformVideoDetailView(video: v.asPlatformVideo, teacherName: teacherName,
                                    seriesName: folder.name)
        }
    }

    /// Levels in the order they are taught; anything unlabelled last.
    private var sections: [(level: String, videos: [FeedVideo])] {
        let known = Self.levelOrder.compactMap { level -> (String, [FeedVideo])? in
            let vs = folder.videos.filter { $0.level == level }.sorted { $0.title < $1.title }
            return vs.isEmpty ? nil : (level, vs)
        }
        let other = folder.videos.filter { !Self.levelOrder.contains($0.level) }.sorted { $0.title < $1.title }
        return known + (other.isEmpty ? [] : [("More", other)])
    }

    private func row(_ v: FeedVideo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: v.dancers > 1 ? "figure.socialdance" : "figure.dance")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.orange)
                .frame(width: 40, height: 40)
                .background(Color.orange.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(v.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(v.duration)\(v.dancers > 1 ? " · couple" : " · solo")")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            if inLessons.contains(v.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .accessibilityLabel("In your lessons")
            } else {
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
