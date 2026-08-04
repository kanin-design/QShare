import Foundation
import Network
import Security

/// A tiny localhost-only JSON API so a `qshare` CLI (or any tool/AI) can drive
/// the running app: list visible devices and send files. Bound to loopback and
/// guarded by a per-machine token in ~/.config/qshare/token.
///
/// Endpoints:
///   GET  /devices                          → [{name,id,type,trusted}]
///   GET  /transfers                        → [{title,device,phase,percent}]
///   POST /send  {"path"|"paths":…, "to":…} → blocks until done → {ok,pin,error}
///   GET  /health                           → {ok:true}
@MainActor
final class ControlServer {
    nonisolated static let port: UInt16 = 47821
    /// Gates the /debug/* routes. Two independent conditions, not one:
    /// `#if DEBUG` means a release build can never compile this `true` no
    /// matter what's in the environment when it's launched — the QS_MOCK
    /// check alone was a *runtime* gate, so a shipped release binary
    /// launched with `QS_MOCK=1` set would still have exposed them.
    #if DEBUG
    nonisolated static let debugEndpointsEnabled = ProcessInfo.processInfo.environment["QS_MOCK"] != nil
    #else
    nonisolated static let debugEndpointsEnabled = false
    #endif
    private var listener: NWListener?
    private unowned let model: AppModel
    let token: String

    init(model: AppModel) {
        self.model = model
        self.token = ControlServer.loadOrCreateToken()
    }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind the socket to 127.0.0.1 specifically, so the port is not even
        // connectable from other hosts (not just filtered at accept time).
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .init(rawValue: Self.port)!)
        guard let l = try? NWListener(using: params) else {
            NSLog("QShare control server: could not bind port \(Self.port)")
            return
        }
        listener = l
        l.newConnectionHandler = { [weak self] conn in
            // Defense in depth: only ever serve loopback peers.
            guard Self.isLoopback(conn.endpoint) else { conn.cancel(); return }
            conn.start(queue: .main)
            MainActor.assumeIsolated {
                self?.armIdleTimeout(conn)
                self?.receive(conn, buffer: Data())
            }
        }
        l.start(queue: .main)
    }

    /// A client that connects and then says nothing must not hold the socket
    /// open indefinitely. `/send` blocks for as long as a transfer takes, so
    /// this only bounds the time to deliver a *complete request*.
    private static let requestTimeout: TimeInterval = 30

    private func armIdleTimeout(_ conn: NWConnection) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.requestTimeout) { [weak self] in
            guard let self, self.pendingConnections.contains(ObjectIdentifier(conn)) else { return }
            self.pendingConnections.remove(ObjectIdentifier(conn))
            conn.cancel()
        }
        pendingConnections.insert(ObjectIdentifier(conn))
    }

    /// Connections whose request hasn't fully arrived yet.
    private var pendingConnections: Set<ObjectIdentifier> = []

    /// Tear the listener down (the API is user-toggleable). In-flight
    /// connections are dropped; parked CLI sends are released by the caller.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static let maxRequestBytes = 256 * 1024

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { conn.cancel(); return }
                var buf = buffer
                if let data { buf.append(data) }
                guard buf.count <= Self.maxRequestBytes else { conn.cancel(); return }   // cap memory
                if let req = HTTPRequest(buf) {
                    // Request is complete; the idle timer has done its job and
                    // must not fire during a long-running /send.
                    self.pendingConnections.remove(ObjectIdentifier(conn))
                    self.route(req) { response in
                        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
                    }
                } else if isComplete || error != nil {
                    self.pendingConnections.remove(ObjectIdentifier(conn))
                    conn.cancel()
                } else {
                    self.receive(conn, buffer: buf)   // keep reading (incomplete body)
                }
            }
        }
    }

    private func route(_ req: HTTPRequest, respond: @escaping (Data) -> Void) {
        // Reject anything not addressed to localhost (DNS-rebinding defense).
        let hostHeader = req.headers["host"] ?? ""
        let hostName = hostHeader.hasPrefix("[")
            ? String(hostHeader.dropFirst().prefix { $0 != "]" })          // [::1]:port → ::1
            : String(hostHeader.split(separator: ":").first ?? "")         // 127.0.0.1:port → 127.0.0.1
        guard ["127.0.0.1", "localhost", "::1", ""].contains(hostName) else {
            respond(Self.json(403, ["error": "bad host"])); return
        }
        // Constant-time bearer-token check.
        let auth = req.headers["authorization"] ?? ""
        guard auth.hasPrefix("Bearer "), Self.constantTimeEqual(String(auth.dropFirst(7)), token) else {
            respond(Self.json(401, ["error": "unauthorized"])); return
        }
        switch (req.method, req.path) {
        case ("GET", "/health"):
            respond(Self.json(200, ["ok": true]))
        case ("GET", "/devices"):
            respond(Self.json(200, model.devicesForCLI()))
        case ("GET", "/transfers"):
            respond(Self.json(200, model.transfersForCLI()))
        case ("POST", "/send"):
            guard let obj = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
                  let to = obj["to"] as? String else {
                respond(Self.json(400, ["error": "expected {paths|path, to}"])); return
            }
            let paths = (obj["paths"] as? [String]) ?? (obj["path"] as? String).map { [$0] } ?? []
            model.cliSend(paths: paths, to: to) { result in
                respond(Self.json(result.ok ? 200 : 502,
                                  ["ok": result.ok, "pin": result.pin as Any, "error": result.error as Any]))
            }
        // Debug-only: exist only under QS_MOCK, so this never ships reachable
        // in a real build. Lets an incoming-request/notification round trip
        // be tested with one `curl` call instead of a manual GUI run —
        // reopening a closed window and checking for a system notification
        // aren't things you can otherwise script.
        case ("POST", "/debug/incoming-request") where Self.debugEndpointsEnabled:
            let obj = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any]) ?? [:]
            model.debugFireIncomingRequest(
                deviceName: (obj["device"] as? String) ?? "Debug Phone",
                files: (obj["files"] as? [String]) ?? [],
                bytes: (obj["bytes"] as? Int).map(Int64.init) ?? 2_400_000,
                pin: (obj["pin"] as? String) ?? String(format: "%04d", Int.random(in: 0...9999)))
            respond(Self.json(200, ["ok": true]))
        case ("GET", "/debug/notifications") where Self.debugEndpointsEnabled:
            model.debugNotificationStatus { delivered, authorization in
                respond(Self.json(200, ["authorization": authorization, "delivered": delivered]))
            }
        default:
            respond(Self.json(404, ["error": "not found"]))
        }
    }

    // MARK: Helpers

    private static func json(_ status: Int, _ obj: Any) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .fragmentsAllowed])) ?? Data()
        var head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8); out.append(body); return out
    }

    /// Only accept connections whose remote peer is the loopback address.
    nonisolated static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let a): return a.isLoopback
        case .ipv6(let a): return a.isLoopback
        case .name(let n, _): return n == "localhost"
        @unknown default: return false
        }
    }

    /// Length-safe, constant-time string comparison (avoids token timing leaks).
    /// Pure — `nonisolated` so it is callable (and testable) off the main actor.
    nonisolated static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    static func loadOrCreateToken() -> String {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/qshare")
        let file = dir.appendingPathComponent("token")
        if let existing = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count >= 32 {
            // Re-assert the mode every load, not only on create. This token is
            // the whole access control on an API whose /send can read any file
            // this user can and push it to a nearby device — so a file left
            // group/world-readable by an older build, a restored backup or a
            // synced home directory hands that to any other local account.
            restrictPermissions(directory: dir, file: file)
            return existing
        }
        // 256-bit token from the system CSPRNG.
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? token.write(to: file, atomically: true, encoding: .utf8)
        restrictPermissions(directory: dir, file: file)
        return token
    }

    /// Owner-only, for both the token and the directory holding it.
    private static func restrictPermissions(directory: URL, file: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

/// Minimal HTTP/1.1 request parser. Returns nil while the request is incomplete.
/// Internal rather than private so the parser can be tested directly — it is the
/// component that reads untrusted bytes.
struct HTTPRequest {
    let method: String, path: String
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)),
              let headerStr = String(data: data.subdata(in: 0..<sep.lowerBound), encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        let reqParts = lines.first?.split(separator: " ") ?? []
        guard reqParts.count >= 2 else { return nil }
        method = String(reqParts[0])
        path = String(reqParts[1].split(separator: "?").first ?? "")
        var h: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let c = line.firstIndex(of: ":") else { continue }
            h[line[..<c].trimmingCharacters(in: .whitespaces).lowercased()] =
                String(line[line.index(after: c)...]).trimmingCharacters(in: .whitespaces)
        }
        headers = h
        let avail = data.subdata(in: sep.upperBound..<data.count)
        let length = Int(h["content-length"] ?? "0") ?? 0
        guard avail.count >= length else { return nil }   // body not fully arrived
        body = avail.prefix(length)
    }
}
