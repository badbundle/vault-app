import Foundation
import SnapshotTesting
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import Testing
#endif

/// Expected device configuration for snapshot tests.
/// This must match the configuration specified in Vault/README.md.
private let expectedDeviceName = "iPhone 18 Pro Max"
private let expectedIOSVersion = "27.0"
/// The Mac's snapshot tests run on this major version of macOS.
private let expectedMacOSMajorVersion = 27
private let expectedLocaleIdentifier = "en_US"
private let expectedTimezoneIdentifier = ["UTC", "GMT"]

/// Asserts that a snapshot matches a reference, but first validates the device configuration.
///
/// This function wraps SnapshotTesting's `assertSnapshot` and adds a runtime check to ensure
/// snapshot tests are running on the correct device and iOS version as specified in the README, or on the Mac, the
/// macOS version the README names.
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

#if !canImport(UIKit) && canImport(AppKit)
/// Asserts that an image snapshot matches a reference made on the Mac, after checking the Mac's configuration.
///
/// The Mac draws differently from the iPhone, so its images are kept apart, in a `macOS` folder beside each test
/// file's iOS images. Text and other snapshots are the same on both, so they share one reference.
@MainActor
public func assertSnapshot<Value>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, NSImage>,
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

    let testFile = URL(filePath: "\(filePath)")
    let snapshotDirectory = testFile.deletingLastPathComponent()
        .appending(path: "__Snapshots__")
        .appending(path: testFile.deletingPathExtension().lastPathComponent)
        .appending(path: "macOS")
    let failure = try verifySnapshot(
        of: value(),
        as: snapshotting,
        named: name,
        snapshotDirectory: snapshotDirectory.path(percentEncoded: false),
        timeout: timeout,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column,
    )
    if let failure {
        Issue.record(
            Comment(rawValue: failure),
            sourceLocation: SourceLocation(
                fileID: "\(fileID)",
                filePath: "\(filePath)",
                line: Int(line),
                column: Int(column),
            ),
        )
    }
}
#endif

/// Validates that the current device matches the expected configuration for snapshot testing.
///
/// - Throws: `fatalError` if the device name, iOS version, locale, timezone, or appearance doesn't match expectations
@MainActor
private func assertDeviceConfiguration(
    file: StaticString = #file,
    line: UInt = #line,
) {
    #if canImport(UIKit)
    assertIOSDeviceConfiguration(file: file, line: line)
    #else
    assertMacConfiguration(file: file, line: line)
    #endif
    assertLocaleAndTimezone(file: file, line: line)
}

#if canImport(UIKit)
@MainActor
private func assertIOSDeviceConfiguration(file: StaticString, line: UInt) {
    let currentDevice = UIDevice.current
    let deviceName = currentDevice.name
    let systemVersion = currentDevice.systemVersion

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
}
#else
@MainActor
private func assertMacConfiguration(file: StaticString, line: UInt) {
    let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    guard majorVersion == expectedMacOSMajorVersion else {
        fatalError(
            """
            ❌ Snapshot test macOS version mismatch!
            Expected: macOS \(expectedMacOSMajorVersion)
            Actual: macOS \(majorVersion)

            Please run snapshot tests on macOS \(expectedMacOSMajorVersion) as specified in Vault/README.md
            """,
            file: file,
            line: line,
        )
    }
}
#endif

/// The test plans set these, on iOS and the Mac.
@MainActor
private func assertLocaleAndTimezone(file: StaticString, line: UInt) {
    let currentLocale = Locale.current.identifier
    let currentTimezone = TimeZone.current.identifier

    guard currentLocale == expectedLocaleIdentifier else {
        fatalError(
            """
            ❌ Snapshot test locale mismatch!
            Expected: \(expectedLocaleIdentifier)
            Actual: \(currentLocale)

            Please configure the simulator locale to English (United States). The test plans set it.
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
