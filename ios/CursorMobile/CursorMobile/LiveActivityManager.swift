import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activities: [String: Activity<AgentActivityAttributes>] = [:]

    func upsert(thread: ThreadSummary, permissionId: String = "") {
        let state = AgentActivityAttributes.ContentState(
            status: liveStatus(thread.status, permissionId: permissionId),
            lastLine: thread.preview,
            elapsed: max(0, Date().timeIntervalSince1970 - thread.createdAt / 1000),
            runningSubagentCount: thread.runningSubagentCount ?? 0,
            runningSubagentName: thread.runningSubagentName ?? "",
            permissionRequestId: permissionId
        )
        let attrs = AgentActivityAttributes(
            agentName: thread.name,
            workspace: thread.workspaceName,
            model: thread.model ?? "",
            threadId: thread.id
        )
        if let existing = activities[thread.id] {
            Task { await existing.update(.init(state: state, staleDate: Date().addingTimeInterval(120))) }
            return
        }
        do {
            let activity = try Activity.request(attributes: attrs, content: .init(state: state, staleDate: Date().addingTimeInterval(120)))
            activities[thread.id] = activity
        } catch {
            /* simulator / unsigned may reject */
        }
    }

    func end(threadId: String) {
        guard let activity = activities.removeValue(forKey: threadId) else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func liveStatus(_ status: ThreadStatus, permissionId: String) -> String {
        if !permissionId.isEmpty { return "waitingForPermission" }
        switch status {
        case .running: return "working"
        case .waiting, .needsAttention, .error: return "needsAttention"
        default: return "finished"
        }
    }
}
