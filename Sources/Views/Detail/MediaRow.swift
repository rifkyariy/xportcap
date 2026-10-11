import SwiftUI
import AppKit

/// One encrypted file: icon, name, one line of status, a quiet export menu.
struct MediaRow: View {
    @Environment(ExportQueue.self) private var exports
    let file: URL
    let project: Project
    let title: String
    @State private var hover = false

    private var state: JobState { exports.jobs[file] ?? .idle }
    private var isAudio: Bool { file.pathExtension.lowercased() == "wav" }
    private var hasAlpha: Bool { !isAudio && Exporter.alphaCompanion(file) != nil }
    private var progress: Double? { if case .working(_, let f) = state { f } else { nil } }
    private var isDone: Bool { if case .done = state { true } else { false } }

    private var icon: String {
        switch state {
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        default: isAudio ? "waveform" : "film"
        }
    }

    private var iconStyle: AnyShapeStyle {
        switch state {
        case .done: AnyShapeStyle(.green)
        case .failed: AnyShapeStyle(.orange)
        default: AnyShapeStyle(.secondary)
        }
    }

    private var details: String {
        switch state {
        case .idle:
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            return [size, hasAlpha ? "Transparency" : nil].compactMap { $0 }.joined(separator: " · ")
        case .working(let m, _): return m
        case .done(let u): return "Saved · \(u.lastPathComponent)"
        case .failed(let m): return m
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconStyle)
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isDone)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(details)
                    .font(.caption).foregroundStyle(state.isFailed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1).truncationMode(.middle)
                    .contentTransition(.opacity)
            }
            .help(file.lastPathComponent)

            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(hover ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear))
        .overlay(alignment: .bottom) {
            // progress as a hairline along the row's bottom edge
            if let f = progress {
                GeometryReader { g in
                    Rectangle().fill(.primary.opacity(0.7)).frame(width: g.size.width * f)
                }
                .frame(height: 2)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .animation(.easeInOut(duration: 0.25), value: progress == nil)
        .animation(.spring(duration: 0.4), value: isDone)
        .contextMenu {
            if isAudio {
                Button("Export WAV", systemImage: "waveform") { exports.export(file, of: project) }
            } else {
                ForEach(ExportFormat.allCases) { fmt in
                    Button("Export as \(fmt.title)", systemImage: fmt.symbol) { exports.export(file, of: project, as: fmt) }
                }
            }
            Divider()
            Button("Show Original in Finder", systemImage: "magnifyingglass") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .working(_, let f):
            Text(f, format: .percent.precision(.fractionLength(0)))
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .contentTransition(.numericText(value: f))
        case .done(let url):
            HStack(spacing: 10) {
                Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "play.fill") }.help("Play")
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }.help("Show in Finder")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
        case .idle, .failed:
            exportMenu(state.isFailed ? "Retry" : "Export")
        }
    }

    @ViewBuilder private func exportMenu(_ label: String) -> some View {
        if isAudio {
            Button(label) { exports.export(file, of: project) }
                .buttonStyle(.borderless)
        } else {
            Menu(label) {
                Section("Export as") {
                    ForEach(ExportFormat.allCases) { fmt in
                        Button { exports.export(file, of: project, as: fmt) } label: {
                            Label(fmt.title, systemImage: fmt.symbol)
                            Text(fmt == .prores && hasAlpha ? "With transparency. For editing." : fmt.detail)
                        }
                    }
                }
            } primaryAction: {
                exports.export(file, of: project)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }
}
