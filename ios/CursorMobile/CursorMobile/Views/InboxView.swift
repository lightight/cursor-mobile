import SwiftUI
import Observation

struct CircleIconButton: View {
    var systemName: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.elevated)
                .clipShape(Circle())
        }
    }
}

struct InboxView: View {
    @Environment(AppState.self) private var state
    @State private var pairingCode = ""
    @State private var host = ""
    @State private var port = "17890"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        Text("Inbox")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            navCard(title: "All Agents", count: nil, color: Theme.orange, icon: "arrow.up.left.and.arrow.down.right", status: nil)
                            navCard(title: "Needs Attention", count: state.counts.needsAttention, color: Theme.yellow, icon: "bell.fill", status: .needsAttention)
                            navCard(title: "Working", count: state.counts.working, color: Theme.blue, icon: "circle.hexagongrid.fill", status: .running)
                            navCard(title: "In Review", count: state.counts.inReview, color: Theme.purple, icon: "checkmark.circle.fill", status: .inReview)
                        }
                        Text("Workspaces")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                        VStack(spacing: 0) {
                            ForEach(state.workspaces) { ws in
                                NavigationLink {
                                    AgentListView(title: ws.name, threads: state.threads(in: ws))
                                } label: {
                                    HStack {
                                        Image(systemName: ws.name == "No Repo" ? "house.fill" : "folder")
                                            .foregroundStyle(.white)
                                        Text(ws.name)
                                            .foregroundStyle(.white)
                                        Spacer()
                                        if ws.badge > 0 {
                                            Text("\(ws.badge)")
                                                .foregroundStyle(Theme.muted)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(Theme.muted)
                                    }
                                    .padding(.vertical, 14)
                                }
                                Divider().background(Color.white.opacity(0.08))
                            }
                            Button {
                                state.showPairing = true
                            } label: {
                                HStack {
                                    Image(systemName: "folder.badge.plus")
                                    Text("Add Workspace")
                                    Spacer()
                                }
                                .foregroundStyle(.white)
                                .padding(.vertical, 14)
                            }
                        }
                        Color.clear.frame(height: 90)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                ComposerBar()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: pairingShown) { PairingView() }
            .sheet(isPresented: profileShown) { ProfileView() }
            .sheet(isPresented: searchShown) { SearchView() }
            .sheet(isPresented: contextShown) { ContextSheet() }
            .sheet(isPresented: modelShown) { ModelSheet() }
            .sheet(item: permissionShown) { _ in PermissionSheet() }
            .sheet(item: planShown) { _ in PlanSheet() }
        }
    }

    private var pairingShown: Binding<Bool> {
        Binding(get: { state.showPairing }, set: { state.showPairing = $0 })
    }
    private var profileShown: Binding<Bool> {
        Binding(get: { state.showProfile }, set: { state.showProfile = $0 })
    }
    private var searchShown: Binding<Bool> {
        Binding(get: { state.showSearch }, set: { state.showSearch = $0 })
    }
    private var contextShown: Binding<Bool> {
        Binding(get: { state.showContext }, set: { state.showContext = $0 })
    }
    private var modelShown: Binding<Bool> {
        Binding(get: { state.showModel }, set: { state.showModel = $0 })
    }
    private var permissionShown: Binding<PermissionRequest?> {
        Binding(get: { state.permission }, set: { state.permission = $0 })
    }
    private var planShown: Binding<PlanRequest?> {
        Binding(get: { state.plan }, set: { state.plan = $0 })
    }

    private var header: some View {
        HStack {
            Button { state.showProfile = true } label: {
                Circle()
                    .fill(LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: 36, height: 36)
            }
            Spacer()
            CircleIconButton(systemName: "magnifyingglass") { state.showSearch = true }
            CircleIconButton(systemName: "folder.badge.plus") { state.showPairing = true }
        }
    }

    private func navCard(title: String, count: Int?, color: Color, icon: String, status: ThreadStatus?) -> some View {
        NavigationLink {
            AgentListView(title: title, threads: state.threads(status: status))
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .foregroundStyle(.white)
                        .font(.headline)
                    if let count {
                        Text("\(count)")
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
