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
        ("Product-demo.mp4",    .incoming, 58_000_000),
        ("Ambient-loop.mp3",    .outgoing,  6_200_000),
        ("Screenshot.png",      .incoming,    980_000),
        ("Design-assets.zip",   .outgoing, 24_000_000),
        ("Slides.key",          .incoming, 12_400_000),
    ]
    var demo: [ActiveTransfer] = items.enumerated().map { i, it in
        ActiveTransfer(id: "demo-\(i)", direction: it.1, deviceName: devices[i % devices.count],
                       title: it.0, totalBytes: it.2, fraction: 1, phase: .completed, files: [file(it.0)])
    }

    // One in-progress transfer at the top for a richer screenshot.
    demo.insert(ActiveTransfer(id: "demo-live", direction: .outgoing, deviceName: "Pixel 8 Pro",
                               title: "Travel-video.mov", totalBytes: 84_000_000, fraction: 0.62,
                               phase: .transferring, files: [file("Travel-video.mov")]), at: 0)

    // Two multi-file groups (one sent, one received).
    let g1 = ["Beach-01.jpg", "Beach-02.jpg", "Beach-03.jpg"]
    demo.append(ActiveTransfer(id: "demo-g1", direction: .outgoing, deviceName: "Galaxy Tab S9",
                               title: "3 files", totalBytes: 8_400_000, fraction: 1,
                               phase: .completed, files: g1.map(file)))
    let g2 = ["Clip-01.mp4", "Clip-02.mp4", "Voice-note.m4a", "Cover.png", "Readme.txt"]
    demo.append(ActiveTransfer(id: "demo-g2", direction: .incoming, deviceName: "Galaxy S24",
                               title: "5 files", totalBytes: 210_000_000, fraction: 1,
                               phase: .completed, files: g2.map(file)))
    return demo
    
    }
}
