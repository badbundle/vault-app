import Foundation

/// Why a slot file couldn't be read or written.
public enum VaultSlotFileError: Error, Equatable {
    /// The bytes aren't a slot file: too short, or the wrong magic.
    case notASlotFile
    /// The file is in a format version this app doesn't read, most likely from a newer app.
    case unsupportedVersion(UInt16)
    /// The header, or the file's length, doesn't fit the format.
    case malformed
    /// The slot's key box didn't open. A wrong key, a slot with no vault in it, and a tampered slot look the same.
    case slotDidNotOpen
    /// The key box opened but the body didn't: the file is damaged or has been tampered with.
    case bodyDidNotOpen
    /// The body is compressed in a way this app doesn't know, most likely by a newer app.
    case unsupportedCompression(UInt32)
    /// The slot has been written or rewrapped since it was opened.
    case slotChanged
    /// The compressed payload doesn't fit even the largest slot size.
    case payloadTooLarge
    /// Compressing or decompressing the payload failed.
    case compressionFailed
    /// Sealing a box failed.
    case sealFailed
}
