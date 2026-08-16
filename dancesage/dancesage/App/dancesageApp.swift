import SwiftUI

@main
struct dancesageApp: App {
    @StateObject private var watchedEvents = WatchedEventStore()
    @State private var importMessage = ""
    @State private var importFailed = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchedEvents)
                .onOpenURL { url in
                    importLesson(from: url)
                }
                .alert(importFailed ? "Could Not Import Lesson" : "Lesson Added", isPresented: Binding(
                    get: { !importMessage.isEmpty },
                    set: { if !$0 { importMessage = "" } }
                )) {
                    Button("OK", role: .cancel) { importMessage = "" }
                } message: {
                    Text(importMessage)
                }
        }
    }

    private func importLesson(from url: URL) {
        guard url.pathExtension.lowercased() == Lesson.fileExtension else { return }
        do {
            let lesson = try LessonStore.shared.importLesson(from: url)
            importFailed = false
            importMessage = "“\(lesson.title)” is in your Lessons. Open Lessons from the home screen to practice it."
        } catch {
            importFailed = true
            importMessage = error.localizedDescription
        }
    }
}
