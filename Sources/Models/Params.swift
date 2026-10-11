import Foundation

/// Per-file scramble parameters: byte x is XORed with `key` iff (x mod P) < L (§3).
struct Params: Codable, Hashable { var key: UInt8; var P: Int; var L: Int }
