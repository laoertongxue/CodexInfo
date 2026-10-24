import Foundation

/// A short, stable hash of a raw payload.
///
/// The normalized signal keeps the hash of the payload the adapter read, so
/// two records can be told apart by their origin. The hash is an FNV-1a
/// checksum: it needs no dependency and stays the same on every platform.
public enum PayloadHash {
    /// The hash of the given bytes, as 16 hex characters.
    public static func short(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    /// The hash of the given text, as 16 hex characters.
    public static func short(_ string: String) -> String {
        short(Data(string.utf8))
    }
}
