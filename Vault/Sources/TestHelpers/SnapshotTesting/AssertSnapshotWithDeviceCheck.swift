#if canImport(UIKit)
import Foundation
import SnapshotTesting
import UIKit

/// Expected device configuration for snapshot tests.
/// This must match the configuration specified in Vault/README.md.
private let expectedDeviceName = "iPhone 17 Pro"
private let expectedIOSVersion = "27.0"
private let expectedLocaleIdentifier = "en_US"
private let expectedTimezoneIdentifier = ["UTC", "GMT"]

/// Asserts that a snapshot matches a reference, but first validates the device configuration.
///
/// This function wraps SnapshotTesting's `assertSnapshot` and adds a runtime check to ensure
/// snapshot tests are running on the correct device and iOS version as specified in the README.
///
/// - Parameters:
///   - value: The value to snapshot
///   - snapshotting: The strategy for snapshotting
///   - name: An optional name for the snapshot
///   - recording: Whether to record a new snapshot
///   - timeout: The amount of time to wait for expectations
///   - fileID: The file ID (automatically captured)
///   - file: The file path (automatically captured)
///   - testName: The test name (automatically captured)
///   - line: The line number (automatically captured)
///   - column: The column number (automatically captured)
@MainActor
public func assertSnapshot<Value>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, some Any>,
    named name: String? = nil,
    timeout: TimeInterval = 5,
    file: StaticString = #file,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) {
    assertDeviceConfiguration(file: file, line: line)

    try SnapshotTesting.assertSnapshot(
        of: value(),
        as: snapshotting,
        named: name,
        timeout: timeout,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column,
    )
}

/// Validates that the current device matches the expected configuration for snapshot testing.
///
/// - Throws: `fatalError` if the device name, iOS version, locale, timezone, or appearance doesn't match expectations
@MainActor
private func assertDeviceConfiguration(
    file: StaticString = #file,
    line: UInt = #line,
) {
    let currentDevice = UIDevice.current
    let deviceName = currentDevice.name
    let systemVersion = currentDevice.systemVersion
    let currentLocale = Locale.current.identifier
    let currentTimezone = TimeZone.current.identifier

    guard deviceName == expectedDeviceName else {
        fatalError(
            """
            ❌ Snapshot test device mismatch!
            Expected: \(expectedDeviceName)
            Actual: \(deviceName)

            Please run snapshot tests on \(expectedDeviceName) as specified in Vault/README.md
            """,
            file: file,
            line: line,
        )
    }

    guard systemVersion == expectedIOSVersion else {
        fatalError(
            """
            ❌ Snapshot test iOS version mismatch!
            Expected: iOS \(expectedIOSVersion)
            Actual: iOS \(systemVersion)

            Please run snapshot tests on iOS \(expectedIOSVersion) as specified in Vault/README.md
            """,
            file: file,
            line: line,
        )
    }

    guard currentLocale == expectedLocaleIdentifier else {
        fatalError(
            """
            ❌ Snapshot test locale mismatch!
            Expected: \(expectedLocaleIdentifier)
            Actual: \(currentLocale)

            Please configure the simulator locale to English (United States).
            """,
            file: file,
            line: line,
        )
    }

    guard expectedTimezoneIdentifier.contains(currentTimezone) else {
        fatalError(
            """
            ❌ Snapshot test timezone mismatch!
            Expected: \(expectedTimezoneIdentifier)
            Actual: \(currentTimezone)

            Please configure the simulator timezone to a valid timezone.
            """,
            file: file,
            line: line,
        )
    }
}

#endif // canImport(UIKit)
