import SwiftUI
import Observation

struct PermissionSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let req = state.permission {
                    Text(req.subagentName.map { "\($0) needs permission" } ?? "Permission required")
                        .font(.title2.bold())
                    Text(req.title)
                        .font(.headline)
                    ScrollView {
                        Text(req.detail)
                            .font(.body)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let ws = req.workspace {
                        Text(ws).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Text("Permission mode")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 8)
                    Picker("Permission mode", selection: approvalBinding) {
                        ForEach(ApprovalMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Button("No") { CompanionClient.shared.decidePermission("reject-once"); dismiss() }
                            .buttonStyle(PermissionButton(color: Theme.red))
                        Button("Yes") { CompanionClient.shared.decidePermission("allow-once"); dismiss() }
                            .buttonStyle(PermissionButton(color: Theme.blue))
                    }
                    Button("Always allow") { CompanionClient.shared.decidePermission("allow-always"); dismiss() }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.bg)
            .navigationTitle("Approve")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var approvalBinding: Binding<ApprovalMode> {
        Binding(
            get: { state.approvalMode },
            set: { CompanionClient.shared.setApprovalMode($0) }
        )
    }
}

struct PermissionButton: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .font(.headline)
    }
}

struct PlanSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let plan = state.plan {
                        Text(plan.name ?? "Plan")
                            .font(.title2.bold())
                        if let overview = plan.overview {
                            Text(overview).foregroundStyle(Theme.muted)
                        }
                        Text(plan.plan)
                            .foregroundStyle(.white)
                    }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button("Build") { CompanionClient.shared.decidePlan(accept: true, build: "agent"); dismiss() }
                        .buttonStyle(PermissionButton(color: Theme.blue))
                    Button("Build in Parallel") { CompanionClient.shared.decidePlan(accept: true, build: "multitask"); dismiss() }
                        .buttonStyle(PermissionButton(color: Theme.purple))
                    Button("Reject") { CompanionClient.shared.decidePlan(accept: false, build: nil); dismiss() }
                        .foregroundStyle(Theme.red)
                }
                .padding()
            }
            .navigationTitle("Plan")
        }
        .preferredColorScheme(.dark)
    }
}

struct QuestionSheet: View {
    var request: QuestionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                ForEach(request.questions) { q in
                    Section(q.prompt) {
                        ForEach(q.options) { opt in
                            Button(opt.label) { selected[q.id] = opt.id }
                                .foregroundStyle(selected[q.id] == opt.id ? Theme.blue : .white)
                        }
                    }
                }
            }
            .navigationTitle(request.title)
            .toolbar {
                Button("Send") {
                    let answers = request.questions.map {
                        ["questionId": $0.id, "selectedOptionIds": [selected[$0.id]].compactMap { $0 }] as [String: Any]
                    }
                    CompanionClient.shared.send(type: "question.answer", payload: [
                        "requestId": request.requestId,
                        "answers": answers
                    ])
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
