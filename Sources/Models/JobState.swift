import Foundation

/// Lifecycle of one file's export, as shown in its row.
enum JobState: Equatable {
    case idle, working(String, Double), done(URL), failed(String)
}

extension JobState {
    var isFailed: Bool { if case .failed = self { true } else { false } }
}
