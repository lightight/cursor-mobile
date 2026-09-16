import Foundation
import Network
import Observation

@Observable
@MainActor
final class AppState {
    var paired = false
    var pairingMessage = "Looking for your computer…"
    var computerName = ""
    var userEmail = ""
    var userName = ""
    var workspaces: [Workspace] = []
    var threads: [ThreadSummary] = []
    var counts = InboxCounts(all: 0, needsAttention: 0, working: 0, inReview: 0)
    var models: [AgentModel] = []
    var selectedModel: AgentModel?
    var selectedMode: ConversationMode = .agent
    var approvalMode: ApprovalMode = .autoReview
    var openThread: ThreadDetail?
    var permission: PermissionRequest?
    var plan: PlanRequest?
    var question: QuestionRequest?
    var contextUsage: ContextUsage?
    var searchText = ""
    var showSearch = false
    var showProfile = false
    var showPairing = true
    var showContext = false
    var showModel = false
    var composerText = ""
    var cloudOnlyKey = ""
    var compacting = false
    var billedTokens: Int = 0

    var filteredThreads: [ThreadSummary] {
        if searchText.isEmpty { return threads }
        let q = searchText.lowercased()
        return threads.filter {
            $0.name.lowercased().contains(q) || $0.workspaceName.lowercased().contains(q) || $0.preview.lowercased().contains(q)
        }
    }

    func threads(in workspace: Workspace) -> [ThreadSummary] {
        threads.filter { $0.workspaceId == workspace.id }
    }

    func threads(status: ThreadStatus?) -> [ThreadSummary] {
        guard let status else { return threads }
        if status == .needsAttention {
            return threads.filter { $0.status == .needsAttention || $0.status == .waiting || $0.status == .error || permission?.threadId == $0.id }
        }
        return threads.filter { $0.status == status }
    }
}

@MainActor
final class CompanionClient {
    static let shared = CompanionClient()
    let state = AppState()
    private var browser: NWBrowser?
    private var ws: URLSessionWebSocketTask?
    private var session: URLSession?
    private var discovered: [(String, NWEndpoint)] = []

    func start() {
        browse()
        if let key = Keychain.apiKey, !key.isEmpty {
            state.cloudOnlyKey = key
        }
    }

    func browse() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: "_cursormobile._tcp", domain: nil), using: params)
        b.stateUpdateHandler = { _ in }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.discovered = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint {
                        return (name, result.endpoint)
                    }
                    return nil
                }
                if let first = self?.discovered.first, !(self?.state.paired ?? false) {
                    self?.state.pairingMessage = "Found \(first.0)"
                }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    func connect(host: String, port: Int, code: String) {
        guard let url = URL(string: "ws://\(host):\(port)") else { return }
        let session = URLSession(configuration: .default)
        self.session = session
        let task = session.webSocketTask(with: url)
        ws = task
        task.resume()
        listen()
        send(type: "hello", payload: ["pairingCode": code, "client": "ios", "version": "1.0.0"])
    }

    func connectDiscovered(code: String) {
        guard let endpoint = discovered.first?.1 else {
            state.pairingMessage = "No companion found on this network. Open Cursor Mobile Companion on your computer."
            return
        }
        resolve(endpoint, code: code)
    }

    private func resolve(_ endpoint: NWEndpoint, code: String) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] st in
            if case .ready = st {
                if let inner = conn.currentPath?.remoteEndpoint, case .hostPort(let host, let port) = inner {
                    Task { @MainActor in
                        self?.connect(host: "\(host)", port: Int(port.rawValue), code: code)
                    }
                }
                conn.cancel()
            }
        }
        conn.start(queue: .main)
    }

    func send(type: String, payload: [String: Any]) {
        guard let ws else { return }
        var obj: [String: Any] = ["type": type, "payload": payload]
        obj["id"] = UUID().uuidString
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(text)) { _ in }
    }

    func openThread(_ id: String) {
        send(type: "chats.open", payload: ["id": id])
    }

    func followup() {
        let text = state.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let threadId = state.openThread?.id ?? UUID().uuidString
        send(type: "followup", payload: [
            "threadId": threadId,
            "text": text,
            "mode": state.selectedMode.rawValue,
            "model": ["id": state.selectedModel?.id ?? "composer-2.5"]
        ])
        state.composerText = ""
    }

    func decidePermission(_ option: String) {
        guard let id = state.permission?.requestId else { return }
        send(type: "permission.decide", payload: ["requestId": id, "optionId": option])
        state.permission = nil
    }

    func setApprovalMode(_ mode: ApprovalMode) {
        state.approvalMode = mode
        send(type: "permission.setMode", payload: ["mode": mode.rawValue])
        if mode == .unrestricted {
            state.permission = nil
        }
    }

    func setMode(_ mode: ConversationMode) {
        state.selectedMode = mode
        if let id = state.openThread?.id {
            send(type: "mode.set", payload: ["threadId": id, "mode": mode.rawValue])
        }
    }

    func decidePlan(accept: Bool, build: String?) {
        guard let plan = state.plan else { return }
        var payload: [String: Any] = ["requestId": plan.requestId, "outcome": accept ? "accepted" : "rejected", "threadId": plan.threadId]
        if let build { payload["build"] = build }
        send(type: "plan.decide", payload: payload)
        state.plan = nil
        if accept {
            setMode(build == "multitask" ? .multitask : .agent)
        }
    }

    private func listen() {
        ws?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .failure:
                    self?.state.paired = false
                    self?.state.pairingMessage = "Disconnected from companion"
                    self?.state.showPairing = true
                case .success(let message):
                    if case .string(let text) = message {
                        self?.handle(text)
                    }
                    self?.listen()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        switch env.type {
        case "hello.ok":
            state.paired = true
            state.showPairing = false
            if let d = env.payload.dict {
                state.computerName = d["computerName"]?.decode(String.self) ?? ""
            }
        case "hello.denied":
            state.paired = false
            state.pairingMessage = "Wrong pairing code"
        case "chats.catalog":
            if let data = try? JSONEncoder().encode(env.payload),
               let decoded = try? JSONDecoder().decode(CatalogPayload.self, from: data) {
                state.workspaces = decoded.workspaces
                state.threads = decoded.threads
                state.counts = decoded.counts
                for t in decoded.threads where t.status == .running {
                    LiveActivityManager.shared.upsert(thread: t)
                }
            }
        case "chats.thread":
            if let data = try? JSONEncoder().encode(env.payload),
               let decoded = try? JSONDecoder().decode(ThreadDetail.self, from: data) {
                state.openThread = decoded
                state.selectedMode = decoded.mode
                state.contextUsage = decoded.contextUsage
            }
        case "subagent.upserted":
            if let data = try? JSONEncoder().encode(env.payload),
               let sub = try? JSONDecoder().decode(Subagent.self, from: data),
               var thread = state.openThread {
                if let idx = thread.subagents.firstIndex(where: { $0.id == sub.id }) {
                    thread.subagents[idx] = sub
                } else {
                    thread.subagents.append(sub)
                }
                state.openThread = thread
            }
        case "permission.request":
            if let data = try? JSONEncoder().encode(env.payload),
               let req = try? JSONDecoder().decode(PermissionRequest.self, from: data) {
                state.permission = req
                if let t = state.threads.first(where: { $0.id == req.threadId }) {
                    LiveActivityManager.shared.upsert(thread: t, permissionId: req.requestId)
                }
            }
        case "permission.resolved":
            state.permission = nil
        case "plan.request":
            if let data = try? JSONEncoder().encode(env.payload),
               let req = try? JSONDecoder().decode(PlanRequest.self, from: data) {
                state.plan = req
            }
        case "question.request":
            if let data = try? JSONEncoder().encode(env.payload),
               let req = try? JSONDecoder().decode(QuestionRequest.self, from: data) {
                state.question = req
            }
        case "context.usage":
            state.contextUsage = env.payload.decode(ContextUsage.self)
        case "models.list":
            if let data = try? JSONEncoder().encode(env.payload),
               let decoded = try? JSONDecoder().decode(ModelsPayload.self, from: data) {
                state.models = decoded.items
                if state.selectedModel == nil { state.selectedModel = decoded.items.first }
            }
        case "me":
            if let d = env.payload.dict {
                state.userEmail = d["email"]?.decode(String.self) ?? ""
                state.userName = d["name"]?.decode(String.self) ?? "A Name"
            }
        case "compaction":
            state.compacting = true
        case "stream.delta":
            break
        default:
            break
        }
    }

    func saveCloudKey(_ key: String) {
        Keychain.apiKey = key
        state.cloudOnlyKey = key
    }
}

struct CatalogPayload: Codable {
    var workspaces: [Workspace]
    var threads: [ThreadSummary]
    var counts: InboxCounts
}

struct ModelsPayload: Codable {
    var items: [AgentModel]
}

enum Keychain {
    static var apiKey: String? {
        get { UserDefaults.standard.string(forKey: "cursor.apiKey") }
        set { UserDefaults.standard.set(newValue, forKey: "cursor.apiKey") }
    }
}
