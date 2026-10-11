import Foundation
import AVFoundation

/// Decrypt -> verify -> write in the chosen format. The one entry point the UI and CLI use.
enum Exporter {
    static func alphaCompanion(_ src: URL) -> URL? {
        let u = URL(fileURLWithPath: src.path + ".alpha.mp4")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    static func run(_ src: URL, dest: URL, format: ExportFormat, progress: @escaping Report) async throws {
        // overall bar: decrypt 0–60%, encode/write 60–100%
        func stage(_ lo: Double, _ hi: Double) -> Report { { m, f in progress(m, lo + (hi - lo) * min(1, max(0, f))) } }
        let fm = FileManager.default
        let cached = ParamCache.get(src)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: dest)

        if src.pathExtension.lowercased() == "wav" {
            progress("Reading", 0.05)
            let d = Bytes(try Data(contentsOf: src, options: .alwaysMapped))
            let p = try cached ?? WavSolver.solve(d, progress: stage(0.05, 0.9))
            progress("Writing WAV", 0.95)
            try WavSolver.write(d, p, to: dest)
            ParamCache.set(p, for: src)
            return
        }

        let tmp = fm.temporaryDirectory.appending(path: UUID().uuidString + ".mp4")
        defer { try? fm.removeItem(at: tmp) }
        if let p = cached {
            progress("Decrypting", 0.2)
            try VideoSolver.write(Bytes(try Data(contentsOf: src, options: .alwaysMapped)), p, to: tmp)
        } else {
            let p = try VideoSolver.solve(src, tmp: tmp, progress: stage(0, 0.6))
            ParamCache.set(p, for: src)
        }

        // ProRes with a matte: merge it in as real transparency (video only)
        if format == .prores, let matte = alphaCompanion(src) {
            try await AlphaMerge.write(color: tmp, matte: matte, to: dest, progress: stage(0.6, 1))
            return
        }

        // passthrough rewrites the ftypqt brand to mp4; presets re-encode
        let (preset, type, label): (String, AVFileType, String) = switch format {
        case .original: (AVAssetExportPresetPassthrough, .mp4, "Writing MP4")
        case .h264: (AVAssetExportPreset1920x1080, .mp4, "Encoding H.264")
        case .prores: (AVAssetExportPresetAppleProRes4444LPCM, .mov, "Encoding ProRes")
        }
        guard let s = AVAssetExportSession(asset: AVURLAsset(url: tmp), presetName: preset) else { throw Failure("Export unavailable") }
        let poll = Task {
            while !Task.isCancelled {
                progress(label, 0.6 + 0.4 * Double(s.progress))
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { poll.cancel() }
        try await s.export(to: dest, as: type)
    }
}
