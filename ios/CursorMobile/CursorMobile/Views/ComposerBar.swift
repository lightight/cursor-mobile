import SwiftUI
import Observation

struct ComposerBar: View {
    var followUp = false
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 8) {
            if !followUp {
                HStack(spacing: 8) {
                    modeChip
                    modelChip
                    ContextUsageRing(usage: state.contextUsage)
                        .onTapGesture { state.showContext = true }
                    Spacer()
                }
                .padding(.horizontal, 18)
            }
            HStack(spacing: 10) {
                Button { state.showContext = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Theme.elevated)
                        .clipShape(Circle())
                }
                TextField(followUp ? "Follow up…" : state.selectedMode.placeholder, text: composerBinding, axis: .vertical)
                    .lineLimit(1...5)
                    .foregroundStyle(.white)
                    .onSubmit { CompanionClient.shared.followup() }
                Button { CompanionClient.shared.followup() } label: {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var composerBinding: Binding<String> {
        Binding(get: { state.composerText }, set: { state.composerText = $0 })
    }

    private var modeChip: some View {
        Menu {
            ForEach(ConversationMode.allCases) { mode in
                Button(mode.label) { CompanionClient.shared.setMode(mode) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(state.selectedMode.label)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.elevated)
            .clipShape(Capsule())
        }
    }

    private var modelChip: some View {
        Button { state.showModel = true } label: {
            HStack(spacing: 4) {
                Text(state.selectedModel?.label ?? state.selectedModel?.id ?? "Model")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.elevated)
            .clipShape(Capsule())
        }
    }
}

struct ContextUsageRing: View {
    var usage: ContextUsage?
    var body: some View {
        let p = (usage?.percent ?? 0) / 100
        ZStack {
            Circle().stroke(Theme.elevated, lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(p, 0.02), 1))
                .stroke(p > 0.85 ? Theme.red : Theme.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel("Context usage \(Int(usage?.percent ?? 0)) percent")
    }
}
