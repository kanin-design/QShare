import Foundation

/// A sender we've accepted from before.
///
/// Identified by advertised name, which is all Quick Share gives us — see the
/// note on `AppModel.knownDevices` for what that does and doesn't guarantee.
struct KnownDevice: Codable, Identifiable, Hashable {
    var name: String
    /// Accept files from this sender without asking.
    var autoAccept: Bool

    var id: String { name }
}
