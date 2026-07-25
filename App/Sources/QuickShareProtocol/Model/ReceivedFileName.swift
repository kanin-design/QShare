import Foundation

/// Turns a remote-supplied file name into a safe destination inside the receive
/// directory.
///
/// The name arrives from an unauthenticated peer, so it is treated as hostile:
/// reduced to a single path component, stripped of anything that could redirect
/// a write, and the resulting path is re-checked against the receive directory
/// before it is used.
public enum ReceivedFileName {

    public static let fallbackName = "received_file"
    /// Long names are truncated well below the 255-byte filesystem limit,
    /// leaving room for a " (2)" disambiguator.
    static let maxNameLength = 200

    /// Reduces an arbitrary string to one safe path component.
    public static func sanitize(_ raw: String) -> String {
        // lastPathComponent removes any directory part, including "../".
        var name = (raw as NSString).lastPathComponent

        // A bare root comes back as "/" rather than "", and would otherwise
        // survive separator substitution as a file literally named "_".
        if name == "/" { name = "" }

        // NUL can truncate a path inside C-level APIs; separators would
        // reintroduce structure.
        name = name.replacingOccurrences(of: "\0", with: "")
        name = name.replacingOccurrences(of: "/", with: "_")
        name = name.replacingOccurrences(of: "\\", with: "_")

        // A leading dot would hide the file; a trailing dot or space is
        // significant on other platforms and confusing here.
        while name.hasSuffix(".") || name.hasSuffix(" ") { name = String(name.dropLast()) }

        if name.utf8.count > maxNameLength {
            let ext = (name as NSString).pathExtension
            var base = (name as NSString).deletingPathExtension
            base = String(base.prefix(maxNameLength - ext.count - 1))
            name = ext.isEmpty ? base : "\(base).\(ext)"
        }

        if name.isEmpty || name == "." || name == ".." { name = fallbackName }
        return name
    }

    /// Resolves a non-colliding destination, and refuses anything that would
    /// land outside `directory`.
    public static func uniqueDestination(for sanitizedName: String,
                                         in directory: URL) throws -> URL {
        let base = directory.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        var candidate = base.appendingPathComponent(sanitizedName)
        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            candidate = base.appendingPathComponent(name)
            counter += 1
            guard counter < 10_000 else {
                throw QuickShareError.localFailure("couldn't find a free file name")
            }
        }

        // Belt and braces: confirm the final path really is inside the directory.
        let resolvedParent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
        guard resolvedParent.path == base.path else {
            throw QuickShareError.protocolViolation("rejected a file name that escaped the receive folder")
        }
        return candidate
    }
}
