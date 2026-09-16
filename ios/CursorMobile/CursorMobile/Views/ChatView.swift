import SwiftUI
import Observation

struct ChatView: View {
    var threadId: String
    var title: String
    var nestedSubagent: Subagent? = nil
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if state.compacting {
                        Text("Summarizing older messages…")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    if let nestedSubagent {
                        subagentTimeline(nestedSubagent)
                    } else {
                        ForEach(detail?.bubbles ?? []) { bubble in
                            bubbleView(bubble)
                        }
                        ForEach(detail?.subagents ?? []) { sub in
                            NavigationLink {
                                ChatView(threadId: threadId, title: sub.name, nestedSubagent: sub)
                            } label: {
                                SubagentCard(subagent: sub)
                            }
                        }
                        if let changes = detail?.changes, !changes.isEmpty {
                            changesCard(changes)
                        }
                    }
                    Color.clear.frame(height: 140)
                }
                .padding(16)
            }
            VStack(spacing: 10) {
                if let prs = detail?.pullRequests, !prs.isEmpty {
                    NavigationLink {
                        PullRequestListView(prs: prs)
                    } label: {
                        Label("View \(prs.count) PRs", systemImage: "arrow.triangle.pull")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.purple)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(Capsule().stroke(Theme.purple.opacity(0.7)))
                    }
                }
                ComposerBar(followUp: true)
            }
        }
        .navigationTitle(nestedSubagent?.name ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("View Details") {}
                    Button("Rename") {}
                    Button("Pin") {}
                    Button("Mark Unread") {}
                    Button("Archive") {}
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.white)
                }
            }
        }
        .onAppear { CompanionClient.shared.openThread(threadId) }
        .sheet(item: Binding(get: { state.permission }, set: { state.permission = $0 })) { _ in PermissionSheet() }
        .sheet(item: Binding(get: { state.plan }, set: { state.plan = $0 })) { _ in PlanSheet() }
        .sheet(item: Binding(get: { state.question }, set: { state.question = $0 })) { q in QuestionSheet(request: q) }
    }

    private var detail: ThreadDetail? {
        if state.openThread?.id == threadId { return state.openThread }
        return nil
    }

    @ViewBuilder
    private func bubbleView(_ bubble: Bubble) -> some View {
        if bubble.role == "thinking" || (bubble.thinking?.isEmpty == false) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Thought")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Text(bubble.thinking ?? bubble.text)
                    .foregroundStyle(.white.opacity(0.9))
            }
        } else {
            Text(bubble.text)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func subagentTimeline(_ sub: Subagent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SubagentCard(subagent: sub)
            if let child = detail?.subagents.first(where: { $0.id == sub.id }) {
                Text(child.summary)
                    .foregroundStyle(.white)
            } else {
                Text(sub.status == "working" ? "Working…" : (sub.summary.isEmpty ? "No transcript yet." : sub.summary))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(sub.children ?? []) { child in
                NavigationLink {
                    ChatView(threadId: threadId, title: child.name, nestedSubagent: child)
                } label: {
                    SubagentCard(subagent: child)
                }
            }
        }
    }

    private func changesCard(_ changes: [FileChange]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Changes \(changes.count)")
                    .foregroundStyle(.white)
                    .font(.headline)
                Spacer()
            }
            ForEach(changes.prefix(5)) { change in
                HStack {
                    Text((change.language ?? URL(fileURLWithPath: change.path).pathExtension.uppercased()))
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(URL(fileURLWithPath: change.path).lastPathComponent)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("+\(change.added)")
                        .foregroundStyle(Theme.green)
                    Text("-\(change.removed)")
                        .foregroundStyle(Theme.red)
                }
                .font(.subheadline)
            }
            if changes.count > 5 {
                Text("… \(changes.count - 5) more")
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SubagentCard: View {
    var subagent: Subagent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(subagent.name)
                        .foregroundStyle(.white)
                        .font(.headline)
                    Spacer()
                    Text(subagent.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
                Text(subagent.summary.isEmpty ? subagent.kind : subagent.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var icon: String {
        switch subagent.kind.lowercased() {
        case "explore": return "magnifyingglass"
        case "bash", "shell": return "terminal"
        case "browser": return "safari"
        default: return "person.crop.rectangle.stack"
        }
    }

    private var statusColor: Color {
        switch subagent.status {
        case "working": return Theme.blue
        case "error": return Theme.red
        case "waiting": return Theme.yellow
        default: return Theme.muted
        }
    }
}
