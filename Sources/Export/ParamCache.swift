import Foundation

/// Solved parameters keyed by path + size + mtime, so each file is solved once (§9 Batch).
enum ParamCache {
    private static func key(_ url: URL) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: url.path)
        return "params:\(url.path)|\(a?[.size] ?? 0)|\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
    }

    static func get(_ url: URL) -> Params? {
        UserDefaults.standard.data(forKey: key(url)).flatMap { try? JSONDecoder().decode(Params.self, from: $0) }
    }

    static func set(_ p: Params, for url: URL) {
        UserDefaults.standard.set(try? JSONEncoder().encode(p), forKey: key(url))
    }
}
