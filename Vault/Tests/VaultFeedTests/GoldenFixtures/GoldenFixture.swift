import Foundation
import Testing

/// The golden fixtures in `Fixtures/`: files in the formats the app stores, made once by the app's own code and kept
/// as they are, so a change to a format that old files can't survive fails a test. See `Fixtures/README.md`.
///
/// Tests read them from the test bundle. Only `GoldenFixtureRecorder`, which runs when `VAULT_RECORD_FIXTURES` is set,
/// writes them, into the source tree, and never over one that's there.
enum GoldenFixture {
    struct AlreadyRecorded: Error, CustomStringConvertible {
        var name: String

        var description: String {
            "\(name) is already recorded. A fixture is never made again: a format change adds a new one."
        }
    }

    /// Whether this run records the fixtures that aren't there yet.
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["VAULT_RECORD_FIXTURES"] != nil
    }

    /// A fixture's bytes, from the test bundle.
    static func data(named name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
            "\(name) isn't in the test bundle",
        )
        return try Data(contentsOf: url)
    }

    /// Where a fixture is in the source tree. Tests on the Simulator run on this Mac, so they can write there.
    static func sourceURL(named name: String) -> URL {
        URL(filePath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/\(name)")
    }

    static func isRecorded(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: sourceURL(named: name).path(percentEncoded: false))
    }

    /// Writes a new fixture into the source tree.
    ///
    /// - Throws: `AlreadyRecorded` if it's there already, rather than replacing it.
    static func record(_ data: Data, named name: String) throws {
        guard !isRecorded(name) else { throw AlreadyRecorded(name: name) }
        try data.write(to: sourceURL(named: name), options: .withoutOverwriting)
    }
}
