import Foundation

/// Sample transfers for `QS_MOCK=1`.
///
/// Deliberately neutral — no real filenames, people or devices — because this is
/// what ends up in screenshots. Lives outside AppModel because it's fixture
/// data, not app state.
enum DemoData {

    static func transfers() -> [ActiveTransfer] {
    /// Neutral, demo-safe sample transfers (no real filenames, people, or devices)
    /// so QS_MOCK=1 is presentable for screenshots.

    let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    func file(_ n: String) -> TransferFile { TransferFile(name: n, url: dl.appendingPathComponent(n)) }

    let devices = ["Pixel 8 Pro", "Galaxy S24", "Galaxy Tab S9"]
    // (filename, direction, bytes) — newest first
    let items: [(String, TransferDirection, Int64)] = [
        ("Mountain-sunset.jpg", .outgoing,  1_800_000),
        ("Release-notes.pdf",   .incoming,    320_000),
        ("IMG_2481.heic",       .outgoing,  4_500_000),
    ]
    var demo: [ActiveTransfer] = items.enumerated().map { i, it in
        ActiveTransfer(id: "demo-\(i)", direction: it.1, deviceName: devices[i % devices.count],
                       title: it.0, totalBytes: it.2, fraction: 1, phase: .completed, files: [file(it.0)])
    }

    // One in-progress transfer at the top for a richer screenshot.
    demo.insert(ActiveTransfer(id: "demo-live", direction: .outgoing, deviceName: "Pixel 8 Pro",
                               title: "Travel-video.mov", totalBytes: 84_000_000, fraction: 0.62,
                               phase: .transferring, files: [file("Travel-video.mov")]), at: 0)

    return demo
    
    }
}
