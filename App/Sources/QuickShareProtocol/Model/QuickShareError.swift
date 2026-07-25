import Foundation

/// Everything the protocol layer can fail with.
///
/// Deliberately coarse: the UI only needs to know what to tell the user, and a
/// remote peer should learn as little as possible about why we hung up.
public enum QuickShareError: Error, Equatable, Sendable {
    /// The peer sent something the protocol doesn't allow.
    case protocolViolation(String)
    /// A required field was absent.
    case missingField(String)
    /// HMAC verification failed — the frame was forged or corrupted.
    case authenticationFailed
    /// The UKEY2 handshake could not be completed.
    case handshakeFailed(String)
    /// The connection dropped or timed out.
    case connectionLost
    case timedOut
    /// The peer declined, or we did.
    case rejected(Reason)
    /// A local failure — disk, or a bug on our side.
    case localFailure(String)
    case internalFailure(String)

    public enum Reason: String, Sendable {
        case userRejected
        case userCanceled
        case notEnoughSpace
        case unsupportedType
        case timedOut
    }

    /// Short, user-facing text. Deliberately non-technical.
    public var userMessage: String {
        switch self {
        case .rejected(let reason):
            switch reason {
            case .userRejected:    return "Declined"
            case .userCanceled:    return "Cancelled"
            case .notEnoughSpace:  return "Not enough space"
            case .unsupportedType: return "Unsupported file type"
            case .timedOut:        return "Timed out"
            }
        case .authenticationFailed: return "Couldn't verify the other device"
        case .handshakeFailed:      return "Handshake failed"
        case .connectionLost:       return "Connection lost"
        case .timedOut:             return "Timed out"
        case .protocolViolation, .missingField: return "Protocol error"
        case .localFailure(let m):  return m
        case .internalFailure:      return "Something went wrong"
        }
    }
}
