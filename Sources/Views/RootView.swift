import SwiftUI

/// Sidebar of projects, detail of the selected one, splash on first appearance.
struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(ExportQueue.self) private var exports
    @AppStorage("appearance") private var appearance = "dark"
    @Binding var splashDone: Bool
    @State private var query = ""
    @State private var spin = 0

    private var filtered: [Project] {
        query.isEmpty ? library.projects : library.projects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        main
            .overlay {
                if !splashDone {
                    SplashView()
                        .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 1.08))))
                }
            }
            .task {
                guard !splashDone else { return }
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeInOut(duration: 0.6)) { splashDone = true }
            }
    }

    @ViewBuilder private func section(_ title: String, _ items: [Project]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { p in
                    // own selection instead of List(selection:): the system highlight is accent blue
                    ProjectRow(project: p, locked: library.files[p.id]?.count ?? 0)
                        .contentShape(Rectangle())
                        .onTapGesture { library.selection = p.id }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(library.selection == p.id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                                .padding(.horizontal, 8)
                        )
                }
            }
        }
    }

    private var main: some View {
        @Bindable var library = library
        return NavigationSplitView {
            List {
                section("Locked Media", filtered.filter { (library.files[$0.id]?.count ?? 0) > 0 })
                section("Projects", filtered.filter { (library.files[$0.id]?.count ?? 0) == 0 })
            }
            .solidTopEdge()
            // plain field instead of .searchable: the system search field jumps into the toolbar
            // when the sidebar collapses, which made re-expanding pop instead of slide
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.6)))
                .padding(.horizontal, 10).padding(.bottom, 6)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .overlay {
                if library.projects.isEmpty {
                    ContentUnavailableView("No CapCut Projects", systemImage: "film.stack",
                                           description: Text("Nothing found in ~/Movies/CapCut."))
                }
            }
        } detail: {
            if let p = library.projects.first(where: { $0.id == library.selection }) {
                ProjectDetailView(project: p).id(p.id)
            } else {
                ContentUnavailableView("Select a Project", systemImage: "sidebar.left")
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { spin += 1; withAnimation(.snappy) { library.reload() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise").symbolEffect(.rotate, value: spin)
                }
                Menu {
                    Picker("Appearance", selection: $appearance) {
                        Label("Dark", systemImage: "moon.fill").tag("dark")
                        Label("Light", systemImage: "sun.max.fill").tag("light")
                        Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    }
                    Divider()
                    Button("Choose Output Folder…", systemImage: "folder.badge.gearshape") { exports.chooseOutput() }
                    Button("Open Output Folder", systemImage: "folder") {
                        try? FileManager.default.createDirectory(at: exports.outDir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(exports.outDir)
                    }
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            }
        }
    }
}
