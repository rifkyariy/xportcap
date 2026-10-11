import SwiftUI

/// The CapCut projects on disk and which files in each are encrypted.
@MainActor @Observable
final class Library {
    var projects: [Project] = []
    var files: [Project.ID: [URL]] = [:]
    var selection: Project.ID?

    init() { reload() }

    func reload() {
        projects = ProjectIndex.load()
        files = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, KeyStore.encryptedFiles(in: $0.folder)) })
        if selection == nil || !projects.contains(where: { $0.id == selection }) { selection = projects.first?.id }
    }
}
