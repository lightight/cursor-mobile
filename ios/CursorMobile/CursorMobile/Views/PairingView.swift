import SwiftUI
import Observation

struct PairingView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var host = ""
    @State private var port = "17890"
    @State private var apiKey = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Connect to computer") {
                    Text(state.pairingMessage)
                        .foregroundStyle(Theme.muted)
                    TextField("Pairing code", text: $code)
                        .keyboardType(.numberPad)
                    TextField("Host (optional)", text: $host)
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    Button("Pair with companion") {
                        if host.isEmpty {
                            CompanionClient.shared.connectDiscovered(code: code)
                        } else {
                            CompanionClient.shared.connect(host: host, port: Int(port) ?? 17890, code: code)
                        }
                    }
                }
                Section("Cloud-only (no local chats)") {
                    Text("A companion on your computer is required to fetch desktop and CLI chats. An API key only lists cloud agents.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    SecureField("Cursor API key", text: $apiKey)
                    Button("Save API key") {
                        CompanionClient.shared.saveCloudKey(apiKey)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Connect")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}
