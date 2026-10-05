import AppKit
import Darwin

/// Where Vault's Open and Save panels start: always the user's Documents folder, never the last folder a panel showed,
/// which AppKit remembers for the whole app. That could be where one vault's backups are, and show from another, such
/// as a duress vault (G17).
enum VaultMacPanels {
    static var startingFolder: URL {
        // The real home folder, not the sandbox container's.
        guard let home = getpwuid(getuid())?.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(filePath: String(cString: home), directoryHint: .isDirectory).appending(path: "Documents")
    }

    /// Starts `panel` in the starting folder.
    static func prepare(_ panel: NSSavePanel) {
        panel.directoryURL = startingFolder
    }
}
