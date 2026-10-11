import Foundation

/// crypto_key_store.dat: [4B len][zlib] -> BSON { keys: { n: { uri, ... } } } (§2.2).
enum KeyStore {
    static func encryptedFiles(in folder: URL) -> [URL] {
        guard let raw = try? Data(contentsOf: folder.appending(path: "crypto_key_store.dat")), raw.count > 10,
              // NSData .zlib is raw DEFLATE: skip 4B length + 2B zlib header, drop 4B adler32
              let inflated = try? (raw.subdata(in: 6..<raw.count - 4) as NSData).decompressed(using: .zlib)
        else { return [] }
        let b = Bytes(inflated as Data)
        var off = 0
        guard let keys = doc(b, &off)["keys"] as? [String: Any] else { return [] }
        return keys.values.compactMap { ($0 as? [String: Any])?["uri"] as? String }
            .map { folder.appending(path: $0.hasPrefix("|p") ? String($0.dropFirst(2)) : $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Minimal BSON: document / int32 / string / binary only.
    private static func doc(_ b: Bytes, _ off: inout Int) -> [String: Any] {
        let i32 = { (o: Int) in Int(Int32(bitPattern: UInt32(b[o]) | UInt32(b[o+1]) << 8 | UInt32(b[o+2]) << 16 | UInt32(b[o+3]) << 24)) }
        let end = off + i32(off)
        var out: [String: Any] = [:]
        off += 4
        defer { off = end }
        while off < end - 1, end <= b.count {
            let t = b[off]; off += 1
            guard let z = b[off..<end].firstIndex(of: 0) else { return out }
            let name = String(decoding: b[off..<z], as: UTF8.self); off = z + 1
            switch t {
            case 0x03: out[name] = doc(b, &off)
            case 0x10: out[name] = i32(off); off += 4
            case 0x02: let n = i32(off); off += 4; out[name] = String(decoding: b[off..<off+n-1], as: UTF8.self); off += n
            case 0x05: off += 5 + i32(off)
            default: return out
            }
        }
        return out
    }
}
