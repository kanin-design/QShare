import Foundation

/// Identifies exactly which build is running.
///
/// The values are stamped into the bundle's Info.plist by `build-app.sh`. A
/// binary run outside a bundle (`swift run`) has none of them, and says so
/// rather than inventing a number.
enum BuildInfo {

    /// Marketing version, e.g. "0.1 alpha".
    static let version: String = {
        let short = string(for: "CFBundleShortVersionString") ?? "0.1"
        let stage = string(for: "QSReleaseStage") ?? "alpha"
        return "\(short) \(stage)"
    }()

    /// Monotonic build counter, incremented by every packaging run.
    static let build: String = string(for: "CFBundleVersion") ?? "—"

    /// Short git SHA the build came from; the unambiguous identifier.
    static let commit: String = string(for: "QSGitCommit") ?? "—"

    /// When the bundle was assembled.
    static let builtAt: String = string(for: "QSBuildDate") ?? "—"

    /// True when running from a proper .app rather than `swift run`.
    static var isPackaged: Bool { string(for: "CFBundleVersion") != nil }

    /// One-line summary, matching what the debug panel shows.
    static var summary: String { "\(version) · build \(build) · \(commit)" }

    private static func string(for key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.isEmpty,
              // Unsubstituted placeholders are not information.
              !value.hasPrefix("__") else { return nil }
        return value
    }
}
