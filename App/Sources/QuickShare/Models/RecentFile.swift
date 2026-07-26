import Foundation

/// A file that recently moved through the app, in either direction.
///
/// Persisted so the File menu is still useful after a relaunch — a recents list
/// that empties every launch isn't one.
struct RecentFile: Codable, Identifiable, Hashable {
    let name: String
    /// Stored as a path rather than a URL so the plist stays readable.
    let path: String
    let receivedAt: Date
    let wasIncoming: Bool

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }

    /// The file may have been moved or deleted since; the menu checks this.
    var stillExists: Bool { FileManager.default.fileExists(atPath: path) }
}
