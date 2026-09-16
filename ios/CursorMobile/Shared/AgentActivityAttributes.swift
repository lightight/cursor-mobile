import ActivityKit
import Foundation

public struct AgentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String
        public var lastLine: String
        public var elapsed: TimeInterval
        public var runningSubagentCount: Int
        public var runningSubagentName: String
        public var permissionRequestId: String

        public init(
            status: String,
            lastLine: String,
            elapsed: TimeInterval,
            runningSubagentCount: Int = 0,
            runningSubagentName: String = "",
            permissionRequestId: String = ""
        ) {
            self.status = status
            self.lastLine = lastLine
            self.elapsed = elapsed
            self.runningSubagentCount = runningSubagentCount
            self.runningSubagentName = runningSubagentName
            self.permissionRequestId = permissionRequestId
        }
    }

    public var agentName: String
    public var workspace: String
    public var model: String
    public var threadId: String

    public init(agentName: String, workspace: String, model: String, threadId: String) {
        self.agentName = agentName
        self.workspace = workspace
        self.model = model
        self.threadId = threadId
    }
}
