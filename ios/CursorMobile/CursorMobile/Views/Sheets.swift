import Charts
import Observation
import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Circle()
                        .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 88, height: 88)
                    Text(state.userName.isEmpty ? "A Name" : state.userName)
                        .font(.title.bold())
                    Text(state.userEmail.isEmpty ? "Not signed in" : state.userEmail)
                        .foregroundStyle(Theme.muted)
                    Text(state.computerName.isEmpty ? "Companion not connected" : state.computerName)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)

                    metric("Tokens", value: formatTokens(state.billedTokens))
                    Chart {
                        BarMark(x: .value("W", "Now"), y: .value("T", max(state.billedTokens, 1)))
                            .foregroundStyle(Theme.orange)
                    }
                    .frame(height: 120)
                    .chartYAxis { AxisMarks(position: .trailing) }

                    HStack {
                        metric("Local Agents", value: "\(state.threads.filter { $0.source != .cloud }.count)")
                        Spacer()
                        metric("Cloud Agents", value: "\(state.threads.filter { $0.source == .cloud }.count)")
                    }

                    Group {
                        settingsRow("Manage Plan")
                        settingsRow("Help")
                        settingsRow("Contact Sales")
                    }
                    Button("Sign out") {}.foregroundStyle(.white)
                    Button("Delete Account") {}.foregroundStyle(Theme.red)
                    Text("CURSOR MOBILE COMPANION 1.0.0")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 20)
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(Theme.muted)
            Text(value).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsRow(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: "arrow.up.right")
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 8)
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.0fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct SearchView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(state.filteredThreads) { thread in
                    NavigationLink {
                        ChatView(threadId: thread.id, title: thread.name)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(thread.name).foregroundStyle(.white)
                            Text(thread.workspaceName).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .searchable(text: Binding(get: { state.searchText }, set: { state.searchText = $0 }), prompt: "Agents, workspaces…")
            .navigationTitle("Search")
            .toolbar {
                Button("Close") { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ContextSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Mode") {
                    ForEach(ConversationMode.allCases) { mode in
                        Button {
                            CompanionClient.shared.setMode(mode)
                            dismiss()
                        } label: {
                            HStack {
                                Text(mode.label).foregroundStyle(.white)
                                Spacer()
                                if state.selectedMode == mode {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.blue)
                                }
                            }
                        }
                    }
                }
                Section("Context usage") {
                    if let usage = state.contextUsage {
                        HStack {
                            ContextUsageRing(usage: usage)
                            Text("\(Int(usage.percent))% · \(usage.tokens) / \(usage.windowSize)")
                                .foregroundStyle(Theme.muted)
                        }
                        ForEach(usage.categories) { cat in
                            HStack {
                                Text(cat.label)
                                Spacer()
                                Text("\(cat.tokens)")
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    } else {
                        Text("Context usage appears after the companion reports token counts for this thread.")
                            .foregroundStyle(Theme.muted)
                    }
                }
                Section("Add") {
                    Label("Photos", systemImage: "photo")
                    Label("Screenshots", systemImage: "rectangle.dashed")
                    Label("Camera", systemImage: "camera")
                    Label("Files", systemImage: "doc")
                    Label("MCP Servers", systemImage: "server.rack")
                }
            }
            .navigationTitle("Context")
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

struct ModelSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var fast = true
    @State private var effort = "Extra High"

    var body: some View {
        NavigationStack {
            List {
                ForEach(state.models) { model in
                    Button {
                        state.selectedModel = model
                    } label: {
                        HStack {
                            Text(model.label ?? model.id).foregroundStyle(.white)
                            Spacer()
                            if state.selectedModel?.id == model.id {
                                Image(systemName: "checkmark").foregroundStyle(Theme.blue)
                            }
                        }
                    }
                }
                Toggle("Fast", isOn: $fast)
                HStack {
                    Text("Effort")
                    Spacer()
                    Text(effort).foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle(state.selectedModel?.id ?? "Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

struct PullRequestListView: View {
    var prs: [PullRequest]
    var body: some View {
        List(prs) { pr in
            NavigationLink {
                PullRequestDetailView(pr: pr)
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.pull").foregroundStyle(Theme.purple)
                    VStack(alignment: .leading) {
                        Text("#\(pr.number) \(pr.title)").foregroundStyle(.white)
                        HStack {
                            Text("+\(pr.added)").foregroundStyle(Theme.green)
                            Text("-\(pr.removed)").foregroundStyle(Theme.red)
                        }
                        .font(.caption)
                    }
                }
            }
            .listRowBackground(Theme.bg)
        }
        .navigationTitle("Pull Requests")
        .preferredColorScheme(.dark)
    }
}

struct PullRequestDetailView: View {
    var pr: PullRequest
    @State private var tab = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(pr.status.capitalized)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.purple.opacity(0.3))
                        .clipShape(Capsule())
                    Text("+\(pr.added) -\(pr.removed)")
                        .foregroundStyle(Theme.muted)
                }
                Text("\(pr.title) #\(pr.number)")
                    .font(.title2.bold())
                Picker("", selection: $tab) {
                    Text("Overview").tag(0)
                    Text("Discussion").tag(1)
                    Text("Commits").tag(2)
                }
                .pickerStyle(.segmented)
                if tab == 0 {
                    ForEach(pr.files ?? []) { file in
                        HStack {
                            Text(URL(fileURLWithPath: file.path).lastPathComponent)
                            Spacer()
                            Text("+\(file.added)").foregroundStyle(Theme.green)
                            Text("-\(file.removed)").foregroundStyle(Theme.red)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}
