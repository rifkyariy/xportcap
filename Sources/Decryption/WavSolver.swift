import Foundation

/// Recovers (key, P, L) for scrambled 16-bit PCM WAVs. key = file[0] ^ 'R' (§4).
// No decoder oracle for PCM, so boundaries are found by smoothness: XORed samples are noise.
// Each block edge is located to the byte, then P = most common start gap, L = most common run.

enum WavSolver {
    struct Format { let dataOff: Int, channels: Int }

    static func format(_ d: Bytes, key: UInt8) throws -> Format {
        let h = d.prefix(4096).map { $0 ^ key }  // header lives in block 0
        guard h.count > 44, fourcc(h, 0) == "RIFF", fourcc(h, 8) == "WAVE" else { throw Failure("Not a scrambled WAV") }
        var off = 12, ch = 0
        func le(_ o: Int, _ n: Int) -> Int {
            var v = 0
            for i in 0..<n { v |= Int(h[o + i]) << (8 * i) }
            return v
        }
        while off + 8 <= h.count {
            let size = le(off + 4, 4)
            switch fourcc(h, off) {
            case "fmt ":
                guard le(off + 8, 2) == 1, le(off + 22, 2) == 16 else { throw Failure("Only 16-bit PCM WAV is supported") }
                ch = le(off + 10, 2)
            case "data":
                guard ch > 0 else { throw Failure("WAV has no fmt chunk") }
                return Format(dataOff: off + 8, channels: ch)
            default: break
            }
            off += 8 + size + (size & 1)
        }
        throw Failure("WAV data chunk not found")
    }

    /// Sum of |Δ| between consecutive frames of one channel over bytes [lo, hi), XOR applied where `xored(i)`.
    static func cost(_ d: Bytes, _ f: Format, _ lo: Int, _ hi: Int, key: UInt8, xored: (Int) -> Bool) -> Int {
        let stride = 2 * f.channels
        var i = max(f.dataOff, lo); i += (stride - (i - f.dataOff) % stride) % stride
        var prev: Int?, total = 0
        while i + 1 < min(hi, d.count) {
            let a = xored(i) ? d[i] ^ key : d[i], b = xored(i + 1) ? d[i + 1] ^ key : d[i + 1]
            let s = Int(Int16(bitPattern: UInt16(a) | UInt16(b) << 8))
            if let p = prev { total += abs(s - p) }
            prev = s; i += stride
        }
        return total
    }

    static func mode(_ v: [Int]) -> (value: Int, support: Int)? {
        var counts: [Int: Int] = [:]
        for x in v { counts[x, default: 0] += 1 }
        guard let best = counts.max(by: { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }) else { return nil }
        return (best.key, best.value)
    }

    static func solve(_ d: Bytes, progress: Report) throws -> Params {
        let key = d[0] ^ 0x52
        guard d.count > 64, d[1] ^ key == 0x49, d[2] ^ key == 0x46, d[3] ^ key == 0x46 else { throw Failure("Not a scrambled WAV") }
        let f = try format(d, key: key)

        progress("Analysing audio", 0.1)
        let W = 1024
        // 1 = XORed, 0 = plain, -1 = unsure (silence, or a window straddling an edge)
        let cls: [Int] = stride(from: 0, to: d.count, by: W).map { o in
            let p = cost(d, f, o, o + W, key: key) { _ in false }, x = cost(d, f, o, o + W, key: key) { _ in true }
            return x * 10 < p * 6 ? 1 : p * 10 < x * 6 ? 0 : -1
        }

        // coarse edges: last confident window of one state .. first confident window of the other
        var edges: [(lo: Int, hi: Int, rising: Bool)] = [], last = (state: 1, idx: 0)  // offset 0 is always XORed
        for (i, c) in cls.enumerated() where c >= 0 {
            if c != last.state { edges.append((last.idx * W, i * W + W, c == 1)) }
            last = (c, i)
        }

        progress("Locating \(edges.count) block edges", 0.5)
        // exact edge = the split byte that makes the audio around it smoothest
        let exact: [(pos: Int, rising: Bool)] = edges.compactMap { e in
            guard e.hi - e.lo <= 16 * W else { return nil }  // long silence: edge not observable
            let lo = max(0, e.lo - 256), hi = min(d.count, e.hi + 256)
            var best: (b: Int, c: Int)?
            for b in e.lo...e.hi {
                let c = cost(d, f, lo, hi, key: key) { e.rising ? $0 >= b : $0 < b }
                if c < best?.c ?? .max { best = (b, c) }
            }
            return best.map { ($0.b, e.rising) }
        }

        let starts = [0] + exact.filter(\.rising).map(\.pos)
        guard let P = mode(zip(starts, starts.dropFirst()).map { $1 - $0 }.filter { $0 > 0 })?.value
                ?? (exact.contains(where: \.rising) ? nil : d.count + 1)  // one block only: P beyond EOF
        else { throw Failure("Could not find the block period") }
        let runs = exact.filter { !$0.rising }.map { $0.pos - ($0.pos / P) * P }
        guard let L = mode(runs)?.value else { throw Failure("Could not find the block length") }
        return Params(key: key, P: P, L: L)
    }

    /// Decrypt and drop anything past the RIFF size (the bdve trailer).
    static func write(_ d: Bytes, _ p: Params, to url: URL) throws {
        var o = VideoSolver.decryptRange(d, 0, d.count, p)
        let riff = Int(o[4]) | Int(o[5]) << 8 | Int(o[6]) << 16 | Int(o[7]) << 24
        if riff + 8 < o.count { o.removeSubrange((riff + 8)...) }
        try Data(o).write(to: url)
    }
}
