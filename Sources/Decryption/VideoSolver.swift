import Foundation
import AVFoundation
import VideoToolbox

/// Recovers (key, P, L) for scrambled HEVC MP4s (§4, §5).
enum VideoSolver {
    static func memfind(_ d: Bytes, _ p: Bytes) -> Int? {
        d.withUnsafeBytes { h in p.withUnsafeBytes { n in
            memmem(h.baseAddress!, h.count, n.baseAddress!, n.count).map { h.baseAddress!.distance(to: UnsafeRawPointer($0)) }
        } }
    }

    static func loadMoov(_ d: Bytes, key: UInt8) throws -> Bytes {
        let tag = Bytes("moov".utf8)
        var xored = false
        var i = memfind(d, tag)
        if i == nil { i = memfind(d, tag.map { $0 ^ key }); xored = true }
        guard let i, i >= 4 else { throw Failure("No moov box found") }
        let s = i - 4
        let size = u32(d[s..<s+4].map { xored ? $0 ^ key : $0 }, 0)
        guard size > 8, s + size <= d.count else { throw Failure("Bad moov size") }
        var m = Bytes(d[s..<s+size])
        if xored { for j in m.indices { m[j] ^= key } }
        return MP4.fixMoov(m, key: key)
    }

    /// (xor offsets, plain offsets) from HEVC NAL and AAC element-id probes.
    static func probes(_ d: Bytes, key: UInt8, tracks: [MP4.Track]) -> ([Int], [Int]) {
        var xs: [Int] = [], ps: [Int] = []
        if let v = tracks.first(where: { $0.handler == "vide" }) {
            for s in MP4.samples(v) {
                let a = MP4.hevcOK(d, s.off, xor: 0), b = MP4.hevcOK(d, s.off, xor: key)
                if a != b { if b { xs.append(s.off) } else { ps.append(s.off) } }
            }
        }
        if let a = tracks.first(where: { $0.handler == "soun" }) {
            let sm = MP4.samples(a).filter { $0.off < d.count }
            let sizes = sm.map(\.size).sorted()
            if !sizes.isEmpty, sizes[sizes.count / 2] >= 64 {  // tiny frames give noise (§11.9)
                var hist = [Int](repeating: 0, count: 8)
                for s in sm { hist[Int(d[s.off] >> 5)] += 1 }
                let modal = hist.indices.max { hist[$0] < hist[$1] }!
                for s in sm {
                    if Int(d[s.off] >> 5) == modal { ps.append(s.off) }
                    else if Int((d[s.off] ^ key) >> 5) == modal { xs.append(s.off) }
                }
            }
        }
        return (xs.sorted(), ps.sorted())
    }

    typealias Fit = (P: Int, La: Int, Lb: Int)

    /// Residue feasibility: P fits iff max(xor residues) < min(plain residues). L ∈ La...Lb.
    static func solveP(xs: [Int], ps: [Int]) -> [Fit] {
        let all = (xs.map { ($0, 1) } + ps.map { ($0, 0) }).sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        let starts = (1..<max(1, all.count)).filter { all[$0].1 == 1 && all[$0 - 1].1 == 0 }.map { all[$0].0 }
        let gaps = zip(starts, starts.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }.sorted()
        let med = gaps.isEmpty ? 100_000.0
            : gaps.count % 2 == 1 ? Double(gaps[gaps.count / 2]) : Double(gaps[gaps.count / 2 - 1] + gaps[gaps.count / 2]) / 2
        let p10 = gaps.isEmpty ? med : Double(gaps[gaps.count / 10])
        let lo = max(1000, Int(p10 * 0.3)), hi = Int(med * 1.6)
        guard hi >= lo else { return [] }
        let spread = { (v: [Int]) in v.count <= 24 ? v : (0..<24).map { v[Int(Double($0) * Double(v.count) / 24)] } }
        let xsS = spread(xs), psS = spread(ps)
        var sols: [Fit] = []
        for P in lo...hi {
            let m = xsS.reduce(0) { max($0, $1 % P) }
            guard !psS.contains(where: { $0 % P <= m }) else { continue }  // cheap pre-filter
            let mx = xs.reduce(0) { max($0, $1 % P) }, mn = ps.reduce(Int.max) { min($0, $1 % P) }
            if mx < mn { sols.append((P, mx + 1, mn)) }
        }
        return sols
    }

    /// Decrypt bytes [lo, hi) of `d` under the block model.
    static func decryptRange(_ d: Bytes, _ lo: Int, _ hi: Int, _ p: Params) -> Bytes {
        var out = Bytes(d[lo..<hi])
        var b = (lo / p.P) * p.P
        while b < hi {
            let a = max(b, lo), e = min(b + p.L, hi)
            if a < e { for i in a..<e { out[i - lo] ^= p.key } }
            b += p.P
        }
        return out
    }

    /// Full decrypt + strip the bdve trailer (truncate at end of moov).
    static func write(_ d: Bytes, _ p: Params, to url: URL) throws {
        var o = decryptRange(d, 0, d.count, p)
        var off = 0, last = o.count
        while off + 8 <= o.count {
            var size = u32(o, off)
            if size == 1, off + 16 <= o.count { size = u64(o, off + 8) }
            if size < 8 { break }
            if fourcc(o, off + 4) == "moov" { last = off + size }
            off += size
        }
        if last < o.count { o.removeSubrange(last...) }
        try Data(o).write(to: url)
    }

    static func formatDescription(_ t: MP4.Track) throws -> CMVideoFormatDescription {
        guard let hvcC = t.hvcC else { throw Failure("No hvcC") }
        var fd: CMVideoFormatDescription?
        let ext = [kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String: ["hvcC": Data(hvcC)]] as CFDictionary
        let st = CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_HEVC,
                                                width: Int32(t.width), height: Int32(t.height),
                                                extensions: ext, formatDescriptionOut: &fd)
        guard st == noErr, let fd else { throw Failure("Bad HEVC config") }
        return fd
    }

    /// The §5.4(b) oracle: decode one sample in-process.
    static func decodes(_ bytes: Bytes, _ fd: CMVideoFormatDescription) -> Bool {
        var session: VTDecompressionSession?
        guard VTDecompressionSessionCreate(allocator: nil, formatDescription: fd, decoderSpecification: nil,
                                           imageBufferAttributes: nil, outputCallback: nil,
                                           decompressionSessionOut: &session) == noErr, let session else { return false }
        defer { VTDecompressionSessionInvalidate(session) }
        var bb: CMBlockBuffer?, sb: CMSampleBuffer?, size = bytes.count
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: size, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: size,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &bb) == noErr, let bb,
              bytes.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: bb, offsetIntoDestination: 0, dataLength: size) }) == noErr,
              CMSampleBufferCreateReady(allocator: nil, dataBuffer: bb, formatDescription: fd, sampleCount: 1,
                                        sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size, sampleBufferOut: &sb) == noErr, let sb else { return false }
        var ok = false
        let st = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sb, flags: [], infoFlagsOut: nil) { status, _, image, _, _ in
            ok = status == noErr && image != nil
        }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        return st == noErr && ok
    }

    /// §5.5: every frame must decode.
    static func verify(_ url: URL, expected: Int) -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first, let r = try? AVAssetReader(asset: asset) else { return false }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        out.alwaysCopiesSampleData = false
        r.add(out)
        r.startReading()
        var n = 0
        while let sb = out.copyNextSampleBuffer() { if CMSampleBufferGetImageBuffer(sb) != nil { n += 1 } }
        return r.status == .completed && n == expected
    }

    /// Recover (key, P, L), leaving a verified decrypted file at `tmp`.
    static func solve(_ url: URL, tmp: URL, progress: Report) throws -> Params {
        progress("Reading", 0.02)
        let d = Bytes(try Data(contentsOf: url, options: .alwaysMapped))
        guard d.count > 16, d[1] == d[0], d[2] == d[0] else { throw Failure("Not a scrambled MP4") }
        let key = d[0]  // MP4 starts 00 00 00 xx, so file[0] is the key (§4)

        progress("Repairing moov", 0.05)
        let tracks = MP4.tracks(try loadMoov(d, key: key))
        guard let vid = tracks.first(where: { $0.handler == "vide" }), vid.hvcC != nil else { throw Failure("No HEVC video track") }
        let samples = MP4.samples(vid), fd = try formatDescription(vid)

        progress("Probing \(samples.count) frames", 0.08)
        let (xs, ps) = probes(d, key: key, tracks: tracks)
        guard !xs.isEmpty, !ps.isEmpty else { throw Failure("Not enough probes") }

        progress("Fitting block period", 0.12)
        // keep the highest cluster (lower ones are harmonics), test it from the middle out (§5.3)
        var cluster: [Fit] = []
        for s in solveP(xs: xs, ps: ps).reversed() {
            if let l = cluster.last, l.P - s.P > 1000 { break }
            cluster.append(s)
        }
        guard !cluster.isEmpty else { throw Failure("No feasible block period") }
        let mid = cluster.map(\.P).reduce(0, +) / cluster.count
        cluster.sort { abs($0.P - mid) < abs($1.P - mid) }

        let syncs = samples.filter { $0.sync && $0.off + $0.size <= d.count }
        var sums: [(k: Int, S: Int)] = []  // the oracle pins k·P + L, reuse it across P
        for (i, c) in cluster.enumerated() {
            // a keyframe that fully contains the end of some block k for every L in range
            guard let (k, s) = syncs.lazy.compactMap({ s -> (Int, MP4.Sample)? in
                let k = max(0, (s.off - c.La + c.P - 1) / c.P)
                return k * c.P + c.La >= s.off && k * c.P + c.Lb < s.off + s.size ? (k, s) : nil
            }).first else { continue }
            let hinted = sums.filter { $0.k == k }.map { $0.S - k * c.P }.filter { (c.La...c.Lb).contains($0) }
            var tried = Set<Int>()
            for L in hinted + Array(c.La...c.Lb) where tried.insert(L).inserted {
                if L % 50 == 0 {
                    let f = (Double(i) + Double(L - c.La) / Double(max(1, c.Lb - c.La))) / Double(cluster.count)
                    progress("Finding decryption key", 0.2 + 0.6 * f)
                }
                let p = Params(key: key, P: c.P, L: L)
                guard decodes(decryptRange(d, s.off, s.off + s.size, p), fd) else { continue }
                sums.append((k, k * c.P + L))
                progress("Verifying all frames", 0.85)
                try write(d, p, to: tmp)
                if verify(tmp, expected: samples.count) { return p }
            }
        }
        throw Failure("Could not pin parameters")
    }
}
