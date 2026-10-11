import Foundation

struct Project: Identifiable, Hashable {
    let id: String
    let name: String
    let folder: URL
    let cover: URL?
    let modified: Date
    let duration: TimeInterval
}
