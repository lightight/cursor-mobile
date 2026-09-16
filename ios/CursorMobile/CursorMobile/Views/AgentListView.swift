import SwiftUI

struct AgentListView: View {
    var title: String
    var threads: [ThreadSummary]

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            List {
                Section("Recents") {
                    ForEach(threads) { thread in
                        NavigationLink {
                            ChatView(threadId: thread.id, title: thread.name)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(thread.unread ? Theme.blue : Theme.muted.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(thread.name)
                                        .foregroundStyle(.white)
                                        .font(.headline)
                                    HStack(spacing: 6) {
                                        if let pr = thread.prUrl, !pr.isEmpty {
                                            Image(systemName: "arrow.triangle.merge")
                                                .foregroundStyle(Theme.purple)
                                            Text("PR")
                                                .foregroundStyle(Theme.muted)
                                        } else {
                                            Text(statusLabel(thread))
                                                .foregroundStyle(Theme.muted)
                                        }
                                        Text("·")
                                            .foregroundStyle(Theme.muted)
                                        Text(thread.workspaceName)
                                            .foregroundStyle(Theme.muted)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .listRowBackground(Theme.bg)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            ComposerBar()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    CircleIconButton(systemName: "magnifyingglass") { CompanionClient.shared.state.showSearch = true }
                    CircleIconButton(systemName: "line.3.horizontal.decrease") {}
                }
            }
        }
        .toolbarBackground(Theme.bg, for: .navigationBar)
    }

    private func statusLabel(_ t: ThreadSummary) -> String {
        switch t.status {
        case .running: return "Working"
        case .waiting: return "Waiting"
        case .error: return "Error"
        case .inReview: return "In Review"
        default: return "No Changes"
        }
    }
}
