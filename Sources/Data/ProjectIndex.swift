import Foundation

/// Reads CapCut's master index, root_meta_info.json (§2.1).
enum ProjectIndex {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Movies/CapCut/User Data/Projects/com.lveditor.draft")

    static func load() -> [Project] {
        guard let d = try? Data(contentsOf: root.appending(path: "root_meta_info.json")),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let all = j["all_draft_store"] as? [[String: Any]] else { return [] }
        return all.compactMap { e -> Project? in
            guard let path = e["draft_fold_path"] as? String else { return nil }
            let us = { (k: String) in (e[k] as? NSNumber)?.doubleValue ?? 0 }  // tm_* are microseconds
            let cover = (e["draft_cover"] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            return Project(id: path, name: e["draft_name"] as? String ?? "Untitled",
                           folder: URL(fileURLWithPath: path), cover: cover,
                           modified: Date(timeIntervalSince1970: us("tm_draft_modified") / 1e6),
                           duration: us("tm_duration") / 1e6)
        }.sorted { $0.modified > $1.modified }
    }
}
