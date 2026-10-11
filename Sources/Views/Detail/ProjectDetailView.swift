import SwiftUI
import AppKit

struct ProjectDetailView: View {
    @Environment(Library.self) private var library
    @Environment(ExportQueue.self) private var exports
    let project: Project
    /// Entrance plays once per project: NavigationSplitView rebuilds the detail when the sidebar toggles.
    @State private var appeared: Bool
    private static var seen: Set<Project.ID> = []

    init(project: Project) {
        self.project = project
        _appeared = State(initialValue: Self.seen.contains(project.id))
    }

    private var files: [URL] { library.files[project.id] ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                if files.isEmpty {
                    nothingLocked
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
                        .animation(.spring(duration: 0.5).delay(0.1), value: appeared)
                } else {
                    mediaHeader
                    Group {
                        section("Clips", videos)
                        section("Audio", audios)
                    }
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                    .animation(.spring(duration: 0.5).delay(0.05), value: appeared)
                    Text("Exports go to \(exports.outDir.path(percentEncoded: false))")
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
            }
            .padding(24)
        }
        .solidTopEdge()
        .navigationTitle(project.name)
        .onAppear { Self.seen.insert(project.id); appeared = true }
    }

    private var videos: [URL] { files.filter { $0.pathExtension.lowercased() == "mp4" } }
    private var audios: [URL] { files.filter { $0.pathExtension.lowercased() == "wav" } }

    /// "Clip 2" / "Audio 1 · vocal": readable names instead of CapCut's UUIDs.
    private func title(for f: URL) -> String {
        if let i = videos.firstIndex(of: f) { return "Clip \(i + 1)" }  // ponytail: index order, add CapCut's timeline names if wanted
        let n = (audios.firstIndex(of: f) ?? 0) + 1
        let tag = f.deletingPathExtension().lastPathComponent.split(separator: "_").last.map(String.init) ?? ""
        return tag.allSatisfy(\.isLetter) && !tag.isEmpty ? tag.capitalized : "Track \(n)"
    }

    /// Grouped like a Settings list: caption header, one rounded panel, inset dividers.
    @ViewBuilder private func section(_ name: String, _ items: [URL]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element) { i, f in
                        if i > 0 { Divider().padding(.leading, 46) }
                        MediaRow(file: f, project: project, title: title(for: f))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var mediaHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Encrypted Media").font(.title2.bold())
                Text([videos.isEmpty ? nil : "\(videos.count) clip\(videos.count == 1 ? "" : "s")",
                      audios.isEmpty ? nil : "\(audios.count) audio"].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Section("Export all clips as") {
                    ForEach(ExportFormat.allCases) { fmt in
                        Button { files.forEach { exports.export($0, of: project, as: fmt) } } label: {
                            Label(fmt.title, systemImage: fmt.symbol)
                            Text(fmt.detail)
                        }
                    }
                }
            } label: {
                Label("Export All", systemImage: "square.and.arrow.down.on.square")
            } primaryAction: {
                files.forEach { exports.export($0, of: project) }
            }
            .menuStyle(.button).buttonStyle(.bordered).fixedSize()
        }
    }

    private var nothingLocked: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, value: appeared)
                .padding(.bottom, 4)
            Text("Nothing to unlock").font(.headline)
            Text("Every file in this project is already playable.\nExport it from CapCut as usual.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.folder]) }
                .buttonStyle(.link).font(.callout)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private var hero: some View {
        Color.clear.frame(height: 230)
            .overlay { Cover(url: project.cover) }
            .overlay { LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(project.name).font(.system(size: 30, weight: .bold, design: .rounded))
                    HStack(spacing: 16) {
                        Label(Duration.seconds(project.duration).formatted(.time(pattern: .minuteSecond)), systemImage: "clock")
                        Label(project.modified.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        Label("\(files.count) locked", systemImage: files.isEmpty ? "lock.open" : "lock")
                    }
                    .font(.callout).opacity(0.9)
                }
                .foregroundStyle(.white).padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }
}
