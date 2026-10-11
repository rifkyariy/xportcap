import SwiftUI

/// Sidebar row: 16:9 cover, name, one quiet line of metadata.
struct ProjectRow: View {
    let project: Project
    let locked: Int

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 64, height: 36)
                .overlay { Cover(url: project.cover) }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).lineLimit(1)
                HStack(spacing: 4) {
                    if locked > 0 {
                        Image(systemName: "lock.fill").imageScale(.small)
                        Text("\(locked) ·")
                    }
                    Text(project.modified, format: .relative(presentation: .named))
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
