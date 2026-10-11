import SwiftUI
import AppKit

/// Headless modes, used for self-checks and by build-app.sh.
enum CLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        // `Xportcap --solve FILE.mp4 ...` : headless self-check of the solver
        if args.count > 2, args[1] == "--solve" {
            for path in args.dropFirst(2) {
                let url = URL(fileURLWithPath: path), t0 = Date()
                let tmp = FileManager.default.temporaryDirectory.appending(path: "xportcap-check.mp4")
                do {
                    let p = url.pathExtension.lowercased() == "wav"
                        ? try WavSolver.solve(Bytes(Data(contentsOf: url)), progress: { m, _ in print("  \(m)") })
                        : try VideoSolver.solve(url, tmp: tmp) { m, _ in print("  \(m)") }
                    print("\(url.lastPathComponent): key=0x\(String(p.key, radix: 16)) P=\(p.P) L=\(p.L) (\(Int(Date().timeIntervalSince(t0)))s)")
                } catch { print("\(url.lastPathComponent): FAILED \(error.localizedDescription)") }
            }
            exit(0)
        }
        // `Xportcap --export SRC DEST [original|h264|prores]` : full pipeline, headless
        if args.count > 3, args[1] == "--export" {
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                do {
                    let format = args.count > 4 ? ExportFormat(rawValue: args[4]) ?? .original : .original
                    try await Exporter.run(URL(fileURLWithPath: args[2]), dest: URL(fileURLWithPath: args[3]), format: format) { m, f in print("  \(Int(f * 100))% \(m)") }
                    print("OK")
                } catch { print("FAILED \(error.localizedDescription)") }
                done.signal()
            }
            done.wait()
            exit(0)
        }
        // `Xportcap --render-icon OUT.png` : used by build-app.sh to make the .icns
        if args.count > 2, args[1] == "--render-icon" {
            MainActor.assumeIsolated {
                let r = ImageRenderer(content: LogoView(size: 1024))
                r.scale = 1
                if let cg = r.cgImage { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[2])) }
            }
            exit(0)
        }
    }
}
