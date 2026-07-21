import Foundation

/// One file queued or in flight.
struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var sizeBytes: Int64

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// Direction of a transfer relative to *this* Mac.
enum TransferDirection {
    case incoming   // Android -> Mac
    case outgoing   // Mac -> Android
}

/// A request from a remote device to send us files. The user must accept/decline.
struct IncomingRequest: Identifiable {
    let id: String            // transfer id from the protocol layer
    let device: RemoteDevice
    let fileNames: [String]
    let totalBytes: Int64
    let pin: String

    var summary: String {
        if fileNames.count == 1 { return fileNames[0] }
        return "\(fileNames.count) files"
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

/// Lifecycle of an active transfer.
enum TransferPhase: Equatable {
    case connecting
    case awaitingConsent   // waiting for the remote user to accept
    case transferring
    case completed
    case failed(String)
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }
}

/// One file within a transfer. `url` is set once we know where it lives on disk
/// (source path for outgoing; saved path for incoming, resolved on completion).
struct TransferFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var url: URL? = nil
}

/// A transfer shown in the UI, incoming or outgoing.
struct ActiveTransfer: Identifiable {
    let id: String
    let direction: TransferDirection
    var deviceName: String
    var title: String        // e.g. "photo.jpg" or "3 files"
    var totalBytes: Int64
    var fraction: Double = 0
    var phase: TransferPhase
    var files: [TransferFile] = []

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    /// Files that exist on disk and can be opened/revealed.
    var openableFiles: [TransferFile] { files.filter { $0.url != nil } }

    /// The single item to reveal for the whole transfer (its containing folder).
    var revealURL: URL? { openableFiles.first?.url }
}
