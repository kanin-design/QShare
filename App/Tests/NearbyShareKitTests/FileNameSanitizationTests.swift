import XCTest
@testable import NearbyShareKit

/// The highest-stakes function in the codebase: it is the only thing standing
/// between a remote-supplied file name and the local filesystem.
final class FileNameSanitizationTests: XCTestCase {

    private func sanitize(_ s: String) -> String {
        InboundNearbyConnection.sanitizeFileName(s)
    }

    // MARK: Ordinary names survive intact

    func testPlainNamesArePreserved() {
        XCTAssertEqual(sanitize("photo.jpg"), "photo.jpg")
        XCTAssertEqual(sanitize("Report 2026 (final).pdf"), "Report 2026 (final).pdf")
        XCTAssertEqual(sanitize("naïve-café-🎉.png"), "naïve-café-🎉.png")
        XCTAssertEqual(sanitize(".hidden"), ".hidden")
    }

    // MARK: Traversal

    func testRelativeTraversalIsStripped() {
        XCTAssertEqual(sanitize("../evil.sh"), "evil.sh")
        XCTAssertEqual(sanitize("../../../../etc/passwd"), "passwd")
        XCTAssertEqual(sanitize("a/b/c/d.txt"), "d.txt")
    }

    func testAbsolutePathsAreStripped() {
        XCTAssertEqual(sanitize("/etc/passwd"), "passwd")
        XCTAssertEqual(sanitize("/Users/someone/.zshrc"), ".zshrc")
    }

    func testBareTraversalTokensAreReplaced() {
        XCTAssertEqual(sanitize(".."), "received_file")
        XCTAssertEqual(sanitize("."), "received_file")
        XCTAssertEqual(sanitize(""), "received_file")
        XCTAssertEqual(sanitize("/"), "received_file")
        XCTAssertEqual(sanitize("../.."), "received_file")
        XCTAssertEqual(sanitize("foo/.."), "received_file")
    }

    func testNulBytesAreRemoved() {
        // A trailing NUL can truncate a path in C-level APIs.
        XCTAssertFalse(sanitize("evil\u{0}.jpg").contains("\u{0}"))
        XCTAssertEqual(sanitize("\u{0}"), "received_file")
    }

    // MARK: The property that actually matters

    /// Whatever the remote sends, joining the sanitized name to the receive
    /// directory must never escape it. This mirrors the guard in
    /// `processIntroductionFrame`.
    func testSanitizedNamesNeverEscapeTheReceiveDirectory() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("qshare-confinement-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.resolvingSymlinksInPath()

        let hostile = [
            "../escape", "../../escape", "/etc/passwd", "..", ".", "", "/",
            "....//....//escape", "a/../../b", "foo/bar/../../../baz",
            "..\\..\\windows", "~/.ssh/authorized_keys", "$HOME/x",
            "con", "..;/etc", "%2e%2e%2fescape", "\u{0}../x",
            String(repeating: "../", count: 64) + "deep",
            String(repeating: "A", count: 4096),
        ]

        for name in hostile {
            let dest = base.appendingPathComponent(sanitize(name))
            XCTAssertTrue(
                dest.resolvingSymlinksInPath().path.hasPrefix(base.path + "/"),
                "name \(name.debugDescription) escaped to \(dest.path)")
            XCTAssertEqual(
                dest.deletingLastPathComponent().resolvingSymlinksInPath().path, base.path,
                "name \(name.debugDescription) landed outside the receive directory")
        }
    }

    /// The sanitized result must always be a single path component.
    func testResultIsAlwaysOneComponent() {
        for name in ["a/b", "/a/b/c", "../x", "x/", "//a//b//"] {
            let out = sanitize(name)
            XCTAssertFalse(out.contains("/"), "\(name.debugDescription) -> \(out)")
            XCTAssertFalse(out.isEmpty)
        }
    }
}
