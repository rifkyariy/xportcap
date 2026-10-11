import Foundation

typealias Bytes = [UInt8]
/// (step label, fraction 0...1)
typealias Report = (String, Double) -> Void

struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ s: String) { errorDescription = s }
}

@inline(__always) func u16(_ b: Bytes, _ o: Int) -> Int { Int(b[o]) << 8 | Int(b[o+1]) }
@inline(__always) func u32(_ b: Bytes, _ o: Int) -> Int { Int(b[o]) << 24 | Int(b[o+1]) << 16 | Int(b[o+2]) << 8 | Int(b[o+3]) }
func u64(_ b: Bytes, _ o: Int) -> Int { u32(b, o) << 32 | u32(b, o + 4) }
func fourcc(_ b: Bytes, _ o: Int) -> String { String(decoding: b[o..<o+4], as: UTF8.self) }
