import SwiftUI
import AppKit

/// Runs exports in the background and publishes each file's progress to the UI.
@MainActor @Observable
final class ExportQueue {
    var jobs: [URL: JobState] = [:]
    var outDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies/xportcap")

    func export(_ file: URL, of project: Project, as format: ExportFormat = .original) {
        if case .working = jobs[file] { return }
        let ext = file.pathExtension.lowercased() == "wav" ? "wav" : format.ext
        let dest = outDir.appending(path: "\(project.name) - \(file.deletingPathExtension().lastPathComponent).\(ext)")
        withAnimation(.spring) { jobs[file] = .working("Starting", 0) }
        Task.detached {
            do {
                try await Exporter.run(file, dest: dest, format: format) { msg, f in
                    Task { @MainActor in
                        if case .working(_, let old) = self.jobs[file] {
                            withAnimation(.linear(duration: 0.15)) { self.jobs[file] = .working(msg, max(old, f)) }
                        }
                    }
                }
                await MainActor.run { withAnimation(.spring(duration: 0.5, bounce: 0.4)) { self.jobs[file] = .done(dest) } }
            } catch {
                await MainActor.run { withAnimation(.spring) { self.jobs[file] = .failed(error.localizedDescription) } }
            }
        }
    }

    func chooseOutput() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Choose"; p.directoryURL = outDir
        if p.runModal() == .OK, let u = p.url { outDir = u }
    }
}
