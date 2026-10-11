import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case original, h264, prores
    var id: Self { self }
    var title: String {
        switch self {
        case .original: "Original (HEVC MP4)"
        case .h264: "H.264 1080p"
        case .prores: "ProRes 4444"
        }
    }
    var detail: String {
        switch self {
        case .original: "Lossless and instant. Same quality as CapCut's render."
        case .h264: "Plays everywhere. Smaller file, re-encoded."
        case .prores: "For editing. Keeps transparency when the clip has it."
        }
    }
    var symbol: String {
        switch self {
        case .original: "film"
        case .h264: "play.rectangle"
        case .prores: "square.stack.3d.up"
        }
    }
    var ext: String { self == .prores ? "mov" : "mp4" }
}
