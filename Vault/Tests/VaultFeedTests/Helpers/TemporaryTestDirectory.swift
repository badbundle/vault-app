import Foundation

/// A new, empty directory of its own for a test's files, so tests running in parallel don't see each other's.
struct TemporaryTestDirectory {
    let url: URL

    init() throws {
        url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// The names of the files in the directory, sorted.
    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).sorted()
    }

    /// Deletes the directory and everything in it.
    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
