import SwiftUI

/// Imported lessons: references shared by a teacher (or by the dancer's other phone).
struct LessonsListView: View {
    @State private var lessons: [Lesson] = []
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if lessons.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "figure.dance")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No lessons yet")
                        .font(.title3.weight(.semibold))
                    Text("When a teacher shares a .dancesage lesson file with you — by AirDrop or in a group chat — open it and it will appear here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            } else {
                List {
                    ForEach(lessons) { lesson in
                        NavigationLink {
                            LessonDetailView(lesson: lesson)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(lesson.title)
                                    .font(.headline)
                                HStack(spacing: 8) {
                                    if !lesson.teacherName.isEmpty {
                                        Label(lesson.teacherName, systemImage: "person.fill")
                                    }
                                    if let bpm = lesson.recording.bpm {
                                        Label("\(Int(bpm)) BPM", systemImage: "metronome")
                                    }
                                    Spacer()
                                    Text(lesson.createdAt, style: .date)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteLesson)
                }
            }
        }
        .navigationTitle("Lessons")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadLessons)
        .alert("Lesson Error", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
    }

    private func loadLessons() {
        do {
            lessons = try LessonStore.shared.load()
        } catch {
            lessons = []
            errorMessage = error.localizedDescription
        }
    }

    private func deleteLesson(at offsets: IndexSet) {
        do {
            lessons = try LessonStore.shared.delete(at: offsets)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
