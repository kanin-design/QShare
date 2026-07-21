import Foundation

/// A device we can share with (discovered over the network) or that is sharing
/// with us. Mirrors NearDrop's `RemoteDeviceInfo` so the real engine maps 1:1.
struct RemoteDevice: Identifiable, Hashable {
    let id: String
    var name: String
    var type: DeviceType

    /// True once we've completed a secure handshake with this peer in this session.
    var isReachable: Bool = true
}

enum DeviceType: String, CaseIterable {
    case phone
    case tablet
    case computer
    case unknown

    /// SF Symbol used to represent the device in lists.
    var symbol: String {
        switch self {
        case .phone:    return "iphone.gen3"
        case .tablet:   return "ipad"
        case .computer: return "laptopcomputer"
        case .unknown:  return "questionmark.circle"
        }
    }
}
