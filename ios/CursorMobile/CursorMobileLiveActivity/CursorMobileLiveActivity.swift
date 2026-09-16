import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CursorMobileLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            lockScreen(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.agentName).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(subtitle(context)).font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.lastLine).lineLimit(2)
                        Spacer()
                        if context.state.status == "waitingForPermission" {
                            Link("No", destination: URL(string: "cursormobile://permission/no")!)
                            Link("Yes", destination: URL(string: "cursormobile://permission/yes")!)
                        }
                    }
                    .font(.subheadline)
                }
            } compactLeading: {
                Image(systemName: context.state.status == "waitingForPermission" ? "exclamationmark.circle.fill" : "circle.hexagongrid.fill")
            } compactTrailing: {
                Text(compact(context)).lineLimit(1)
            } minimal: {
                Image(systemName: "circle.hexagongrid.fill")
            }
        }
    }

    @ViewBuilder
    private func lockScreen(context: ActivityViewContext<AgentActivityAttributes>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.agentName)
                    .font(.headline)
                Text(subtitle(context))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(context.state.lastLine)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            Spacer()
            if context.state.status == "waitingForPermission" {
                VStack {
                    Link("Yes", destination: URL(string: "cursormobile://permission/yes")!)
                    Link("No", destination: URL(string: "cursormobile://permission/no")!)
                }
                .font(.subheadline.bold())
            }
        }
        .padding()
    }

    private func subtitle(_ context: ActivityViewContext<AgentActivityAttributes>) -> String {
        if context.state.status == "waitingForPermission" { return "Waiting for permission" }
        if context.state.runningSubagentCount > 0 {
            let name = context.state.runningSubagentName.isEmpty ? "Subagent" : context.state.runningSubagentName
            return "\(name) · \(context.state.runningSubagentCount) running"
        }
        return "\(context.attributes.workspace) · \(context.attributes.model)"
    }

    private func compact(_ context: ActivityViewContext<AgentActivityAttributes>) -> String {
        if context.state.status == "waitingForPermission" { return "Ask" }
        if context.state.runningSubagentCount > 0 { return "\(context.state.runningSubagentCount)" }
        return String(context.attributes.agentName.prefix(8))
    }
}
