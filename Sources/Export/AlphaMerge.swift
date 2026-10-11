import Foundation
import AVFoundation

/// Decrypted colour + plain .alpha.mp4 matte -> ProRes 4444 .mov with transparency (§9).
enum AlphaMerge {
    static func write(color: URL, matte: URL, to dest: URL, progress: Report) async throws {
        let ca = AVURLAsset(url: color), ma = AVURLAsset(url: matte)
        guard let ct = try await ca.loadTracks(withMediaType: .video).first,
              let mt = try await ma.loadTracks(withMediaType: .video).first else { throw Failure("Missing video track") }
        let size = try await ct.load(.naturalSize)
        let bgra: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let cr = try AVAssetReader(asset: ca), mr = try AVAssetReader(asset: ma)
        let co = AVAssetReaderTrackOutput(track: ct, outputSettings: bgra)
        let mo = AVAssetReaderTrackOutput(track: mt, outputSettings: bgra)
        cr.add(co); mr.add(mo)

        let w = try AVAssetWriter(outputURL: dest, fileType: .mov)
        let wi = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
        wi.transform = try await ct.load(.preferredTransform)
        wi.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: wi, sourcePixelBufferAttributes: nil)
        w.add(wi)
        guard cr.startReading(), mr.startReading(), w.startWriting() else {
            throw Failure((w.error ?? cr.error ?? mr.error)?.localizedDescription ?? "Alpha export failed")
        }

        let total = max(1, Int(try await ct.load(.timeRange).duration.seconds * Double(try await ct.load(.nominalFrameRate))))
        var n = 0, started = false
        while let cs = co.copyNextSampleBuffer() {
            guard let cb = CMSampleBufferGetImageBuffer(cs) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(cs)
            if !started { w.startSession(atSourceTime: pts); started = true }
            if let ms = mo.copyNextSampleBuffer(), let mb = CMSampleBufferGetImageBuffer(ms) { applyMatte(cb, mb) }
            CVBufferSetAttachment(cb, kCVImageBufferAlphaChannelModeKey, kCVImageBufferAlphaChannelMode_StraightAlpha, .shouldPropagate)
            while !wi.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard adaptor.append(cb, withPresentationTime: pts) else { break }
            n += 1
            if n % 15 == 0 { progress("Merging alpha · frame \(n)/\(total)", Double(n) / Double(total)) }
        }
        wi.markAsFinished()
        await w.finishWriting()
        guard w.status == .completed, cr.status == .completed else {
            throw Failure((w.error ?? cr.error)?.localizedDescription ?? "Alpha export failed")
        }
    }

    /// Matte luma (green channel) -> color alpha. Nearest-neighbour if sizes differ.
    static func applyMatte(_ c: CVPixelBuffer, _ m: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(c, []); CVPixelBufferLockBaseAddress(m, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(c, []); CVPixelBufferUnlockBaseAddress(m, .readOnly) }
        guard let cBase = CVPixelBufferGetBaseAddress(c), let mBase = CVPixelBufferGetBaseAddress(m) else { return }
        let w = CVPixelBufferGetWidth(c), h = CVPixelBufferGetHeight(c)
        let mw = CVPixelBufferGetWidth(m), mh = CVPixelBufferGetHeight(m)
        let cs = CVPixelBufferGetBytesPerRow(c), ms = CVPixelBufferGetBytesPerRow(m)
        let cp = cBase.assumingMemoryBound(to: UInt8.self), mp = mBase.assumingMemoryBound(to: UInt8.self)
        let mx = (0..<w).map { ($0 * mw / w) * 4 + 1 }
        for y in 0..<h {
            let crow = cp + y * cs, mrow = mp + (y * mh / h) * ms
            for x in 0..<w { crow[x * 4 + 3] = mrow[mx[x]] }
        }
    }
}
