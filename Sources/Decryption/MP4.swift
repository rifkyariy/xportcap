import Foundation

/// ISO-BMFF box walk, sample tables, adaptive moov repair (§5.1).
enum MP4 {
    static let containers: Set<String> = ["moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "udta"]
    static let known: Set<String> = [
        "mvhd", "trak", "tkhd", "edts", "elst", "mdia", "mdhd", "hdlr", "minf", "vmhd", "smhd", "dinf", "dref",
        "stbl", "stsd", "stts", "stss", "stsc", "stsz", "stco", "co64", "ctts", "sgpd", "sbgp", "udta", "meta",
        "free", "skip", "avc1", "hvc1", "mp4a", "esds", "avcC", "hvcC", "btrt", "pasp", "colr", "sdtp", "ilst",
        "keys", "url ", "wide", "ftyp", "mdat", "moov",
    ]

    typealias Box = (type: String, off: Int, size: Int, hdr: Int)

    static func boxes(_ b: Bytes, _ start: Int, _ end: Int) -> [Box] {
        var out: [Box] = [], off = start
        while off + 8 <= end {
            var size = u32(b, off), hdr = 8
            if size == 1 { guard off + 16 <= end else { break }; size = u64(b, off + 8); hdr = 16 }
            else if size == 0 { size = end - off }
            if size < hdr || off + size > end { break }
            out.append((fourcc(b, off + 4), off, size, hdr))
            off += size
        }
        return out
    }

    /// Payload spans of boxes at `path`.
    static func find(_ b: Bytes, _ s: Int, _ e: Int, _ path: [String]) -> [(Int, Int)] {
        boxes(b, s, e).filter { $0.type == path[0] }.flatMap { x -> [(Int, Int)] in
            path.count == 1 ? [(x.off + x.hdr, x.off + x.size)]
                            : find(b, x.off + x.hdr, x.off + x.size, Array(path.dropFirst()))
        }
    }

    /// Repair a plain / fully / partially XORed moov: per box, pick the state that yields a known 4CC.
    static func fixMoov(_ buf: Bytes, key: UInt8) -> Bytes {
        var out = buf
        func rec(_ start: Int, _ end: Int) {
            var off = start
            while off + 8 <= end {
                var best: (score: Int, xored: Bool, size: Int, type: String)?
                for xored in [false, true] {
                    let h = out[off..<off+8].map { xored ? $0 ^ key : $0 }
                    let size = u32(h, 0), type = fourcc(h, 4)
                    guard size >= 8, size <= end - off else { continue }
                    let score = (known.contains(type) ? 2 : 0) + (h[4..<8].allSatisfy { $0 >= 0x20 && $0 < 0x7f } ? 1 : 0)
                    if score > (best?.score ?? 0) { best = (score, xored, size, type) }
                }
                guard let b = best else { return }
                if b.xored { for i in off..<off + b.size { out[i] ^= key } }
                if containers.contains(b.type) { rec(off + 8, off + b.size) }
                off += b.size
            }
        }
        rec(8, out.count)
        return out
    }

    struct Track {
        var handler = "", codec = ""
        var stco: [Int] = [], stsz: [Int] = [], stsc: [(Int, Int)] = []
        var stss: Set<Int>?
        var width = 0, height = 0
        var hvcC: Bytes?
    }

    static func tracks(_ m: Bytes) -> [Track] {
        find(m, 8, m.count, ["trak"]).map { ts, te in
            var t = Track()
            for (a, _) in find(m, ts, te, ["mdia", "hdlr"]) where a + 12 <= te { t.handler = fourcc(m, a + 8) }
            for (a, b) in find(m, ts, te, ["mdia", "minf", "stbl", "stsd"]) {
                guard let e = boxes(m, a + 8, b).first else { continue }
                t.codec = e.type
                if e.size >= 86 {  // visual sample entry: 78 bytes of fields, then child boxes
                    t.width = u16(m, e.off + 32); t.height = u16(m, e.off + 34)
                    if let c = boxes(m, e.off + 86, e.off + e.size).first(where: { $0.type == "hvcC" }) {
                        t.hvcC = Bytes(m[c.off + c.hdr..<c.off + c.size])
                    }
                }
            }
            for (a, b) in find(m, ts, te, ["mdia", "minf", "stbl"]) {
                for x in boxes(m, a, b) {
                    let p = x.off + x.hdr, end = x.off + x.size
                    guard p + 12 <= end else { continue }
                    // clamp entry counts to what fits in the box: a corrupt count must not crash us
                    let n = { (per: Int, head: Int) in min(u32(m, p + 4), max(0, (end - p - head) / per)) }
                    switch x.type {
                    case "stco": t.stco = (0..<n(4, 8)).map { u32(m, p + 8 + 4 * $0) }
                    case "co64": t.stco = (0..<n(8, 8)).map { u64(m, p + 8 + 8 * $0) }
                    case "stss": t.stss = Set((0..<n(4, 8)).map { u32(m, p + 8 + 4 * $0) })
                    case "stsc": t.stsc = (0..<n(12, 8)).map { (u32(m, p + 8 + 12 * $0), u32(m, p + 12 + 12 * $0)) }
                    case "stsz":
                        let usz = u32(m, p + 4), c = u32(m, p + 8)
                        t.stsz = usz != 0 ? Array(repeating: usz, count: min(c, 10_000_000))
                                          : (0..<min(c, max(0, (end - p - 12) / 4))).map { u32(m, p + 12 + 4 * $0) }
                    default: break
                    }
                }
            }
            return t
        }
    }

    typealias Sample = (off: Int, size: Int, sync: Bool)

    static func samples(_ t: Track) -> [Sample] {
        var out: [Sample] = [], si = 0
        for (e, (fc, spc)) in t.stsc.enumerated() where fc >= 1 {
            let last = e + 1 < t.stsc.count ? t.stsc[e + 1].0 - 1 : t.stco.count
            for c in stride(from: fc, through: last, by: 1) {
                guard c - 1 < t.stco.count else { break }
                var off = t.stco[c - 1]
                for _ in 0..<spc {
                    guard si < t.stsz.count else { return out }
                    out.append((off, t.stsz[si], t.stss?.contains(si + 1) ?? true))
                    off += t.stsz[si]; si += 1
                }
            }
        }
        return out
    }

    /// Does a length-prefixed HEVC NAL start at `off` after XOR with `key` (0 = plain)?
    static func hevcOK(_ d: Bytes, _ off: Int, xor key: UInt8) -> Bool {
        guard off >= 0, off + 6 <= d.count else { return false }
        let b = (0..<6).map { d[off + $0] ^ key }
        let len = u32(b, 0)
        guard len >= 2, off + 4 + len <= d.count else { return false }
        return b[4] & 0x81 == 0 && (b[4] >> 1) & 0x3f <= 40
    }
}
