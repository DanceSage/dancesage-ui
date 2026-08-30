import SwiftUI

/// Imported lessons: references shared by a teacher (or by the dancer's other phone).
///
/// Dressed like the Record page — same ground, same logo — because they are two
/// halves of the same act. Landing on a plain grey list after a purple screen makes
/// one of them feel like a different app.
struct LessonsListView: View {
    @State private var lessons: [Lesson] = []
    @State private var errorMessage = ""
    @State private var confirmDelete: Lesson?

    private let logoBackground = Color(
        red: 81.0 / 255.0,
        green: 63.0 / 255.0,
        blue: 89.0 / 255.0
    )

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

            ScrollView {
                VStack(spacing: 0) {
                    header
                    if lessons.isEmpty { empty } else { list }
                }
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Lessons")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: loadLessons)
        .alert("Lesson Error", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
        .alert("Remove this lesson?", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        ), presenting: confirmDelete) { lesson in
            Button("Remove", role: .destructive) { delete(lesson) }
            Button("Keep", role: .cancel) { confirmDelete = nil }
        } message: { lesson in
            Text("“\(lesson.title)” is removed from this iPhone. Your own recordings are not affected.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 0) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .accessibilityHidden(true)

            Text("Lessons")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(lessons.isEmpty
                 ? "Moves a teacher shared with you."
                 : "Dance inside the move, and hear how close you are.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 34)
        }
        .padding(.top, 8)
        .padding(.bottom, 26)
    }

    private var list: some View {
        VStack(spacing: 12) {
            ForEach(lessons) { lesson in
                NavigationLink {
                    LessonDetailView(lesson: lesson)
                } label: {
                    row(lesson)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Remove lesson", role: .destructive) {
                        confirmDelete = lesson
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func row(_ lesson: Lesson) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 46, height: 46)
                .background(.orange.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(lesson.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    if !lesson.teacherName.isEmpty {
                        Label(lesson.teacherName, systemImage: "person.fill")
                    }
                    if let bpm = lesson.recording.bpm {
                        Label("\(Int(bpm)) BPM", systemImage: "metronome")
                    }
                    Text(lesson.createdAt, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.subheadline.bold())
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)) }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "graduationcap")
                .font(.system(size: 42))
                .foregroundStyle(.white.opacity(0.35))
            Text("No lessons yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("When someone shares a lesson with you — through Dance Sage, or as "
                 + "a file by AirDrop or a group chat — it appears here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
        .padding(.top, 24)
    }

    // MARK: - Work

    private func loadLessons() {
        do {
            lessons = try LessonStore.shared.load()
        } catch {
            lessons = []
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ lesson: Lesson) {
        confirmDelete = nil
        guard let index = lessons.firstIndex(where: { $0.id == lesson.id }) else { return }
        do {
            lessons = try LessonStore.shared.delete(at: IndexSet(integer: index))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
