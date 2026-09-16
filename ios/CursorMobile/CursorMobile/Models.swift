import Foundation

enum ConversationMode: String, Codable, CaseIterable, Identifiable {
    case agent, plan, ask, debug, multitask
    var id: String { rawValue }
    var label: String {
        switch self {
        case .agent: return "Agent"
        case .plan: return "Plan"
        case .ask: return "Ask"
        case .debug: return "Debug"
        case .multitask: return "Multitask"
        }
    }
    var placeholder: String {
        switch self {
        case .ask: return "Ask about the codebase…"
        case .plan: return "Describe what to plan…"
        case .debug: return "Describe the bug…"
        case .multitask: return "Split this into parallel work…"
        default: return "Plan, ask, build…"
        }
    }
}

enum ApprovalMode: String, Codable, CaseIterable, Identifiable {
    case allowlist
    case autoReview = "auto-review"
    case unrestricted
    var id: String { rawValue }
    var label: String {
        switch self {
        case .allowlist: return "Allowlist"
        case .autoReview: return "Auto-review"
        case .unrestricted: return "Run Everything"
        }
    }
}

enum ThreadStatus: String, Codable {
    case running, waiting, needsAttention, inReview, finished, error
}

enum ThreadSource: String, Codable {
    case app, cli, sdk, cloud
}

struct Workspace: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var cwd: String?
    var badge: Int
}

struct Subagent: Identifiable, Codable, Hashable {
    var id: String
    var parentId: String
    var name: String
    var kind: String
    var status: String
    var summary: String
    var elapsedMs: Double?
    var children: [Subagent]?
}

struct Bubble: Identifiable, Codable, Hashable {
    var id: String
    var role: String
    var text: String
    var createdAt: Double
    var toolName: String?
    var thinking: String?
}

struct FileChange: Identifiable, Codable, Hashable {
    var id: String { path }
    var path: String
    var language: String?
    var added: Int
    var removed: Int
}

struct PullRequest: Identifiable, Codable, Hashable {
    var id: String
    var number: Int
    var title: String
    var url: String?
    var status: String
    var added: Int
    var removed: Int
    var files: [FileChange]?
}

struct ContextCategory: Identifiable, Codable, Hashable {
    var id: String
    var label: String
    var tokens: Int
    var percent: Double
}

struct ContextUsage: Codable, Hashable {
    var threadId: String
    var percent: Double
    var tokens: Int
    var windowSize: Int
    var categories: [ContextCategory]
}

struct ThreadSummary: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var cwd: String?
    var workspaceId: String
    var workspaceName: String
    var source: ThreadSource
    var status: ThreadStatus
    var unread: Bool
    var preview: String
    var updatedAt: Double
    var createdAt: Double
    var mode: ConversationMode
    var model: String?
    var gitBranch: String?
    var prUrl: String?
    var added: Int?
    var removed: Int?
    var runningSubagentCount: Int?
    var runningSubagentName: String?
}

struct ThreadDetail: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var cwd: String?
    var workspaceId: String
    var workspaceName: String
    var source: ThreadSource
    var status: ThreadStatus
    var unread: Bool
    var preview: String
    var updatedAt: Double
    var createdAt: Double
    var mode: ConversationMode
    var model: String?
    var gitBranch: String?
    var prUrl: String?
    var added: Int?
    var removed: Int?
    var runningSubagentCount: Int?
    var runningSubagentName: String?
    var bubbles: [Bubble]
    var subagents: [Subagent]
    var changes: [FileChange]
    var pullRequests: [PullRequest]
    var contextUsage: ContextUsage?
    var planMarkdown: String?
}

struct InboxCounts: Codable, Hashable {
    var all: Int
    var needsAttention: Int
    var working: Int
    var inReview: Int
}

struct PermissionRequest: Identifiable, Codable, Hashable {
    var requestId: String
    var threadId: String
    var subagentId: String?
    var subagentName: String?
    var title: String
    var detail: String
    var workspace: String?
    var sandboxed: Bool?
    var id: String { requestId }
}

struct PlanRequest: Identifiable, Codable, Hashable {
    var requestId: String
    var threadId: String
    var name: String?
    var overview: String?
    var plan: String
    var todos: [PlanTodo]
    var id: String { requestId }
}

struct PlanTodo: Codable, Hashable {
    var id: String?
    var content: String?
    var status: String?
}

struct QuestionRequest: Identifiable, Codable, Hashable {
    var requestId: String
    var threadId: String
    var title: String
    var questions: [AgentQuestion]
    var id: String { requestId }
}

struct AgentQuestion: Identifiable, Codable, Hashable {
    var id: String
    var prompt: String
    var options: [QuestionOption]
    var allowMultiple: Bool?
}

struct QuestionOption: Identifiable, Codable, Hashable {
    var id: String
    var label: String
}

struct AgentModel: Identifiable, Codable, Hashable {
    var id: String
    var label: String?
}

struct Envelope: Codable {
    var type: String
    var id: String?
    var payload: JSONValue
}

enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var dict: [String: JSONValue]? {
        if case .object(let d) = self { return d }
        return nil
    }
}

extension JSONValue {
    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
