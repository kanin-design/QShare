import Foundation
import Network

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
    static let port: UInt16 = 47821
    private var listener: NWListener?
    private unowned let model: AppModel
    let token: String

    init(model: AppModel) {
        self.model = model
        self.token = ControlServer.loadOrCreateToken()
    }

    func start() {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback     // localhost only
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: .init(rawValue: Self.port)!) else {
            NSLog("QShare control server: could not bind port \(Self.port)")
            return
        }
        listener = l
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            MainActor.assumeIsolated { self?.receive(conn, buffer: Data()) }
        }
        l.start(queue: .main)
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { conn.cancel(); return }
                var buf = buffer
                if let data { buf.append(data) }
                if let req = HTTPRequest(buf) {
                    self.route(req) { response in
                        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
                    }
                } else if isComplete || error != nil {
                    conn.cancel()
                } else {
                    self.receive(conn, buffer: buf)   // keep reading (incomplete body)
                }
            }
        }
    }

    private func route(_ req: HTTPRequest, respond: @escaping (Data) -> Void) {
        guard req.headers["authorization"] == "Bearer \(token)" else {
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

    static func loadOrCreateToken() -> String {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/qshare")
        let file = dir.appendingPathComponent("token")
        if let existing = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty { return existing }
        let token = UUID().uuidString
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? token.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return token
    }
}

/// Minimal HTTP/1.1 request parser. Returns nil while the request is incomplete.
private struct HTTPRequest {
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
