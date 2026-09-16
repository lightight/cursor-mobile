import Observation
import SwiftUI

@main
struct CursorMobileApp: App {
    @State private var client = CompanionClient.shared

    var body: some Scene {
        WindowGroup {
            InboxView()
                .environment(client.state)
                .preferredColorScheme(.dark)
                .onAppear { client.start() }
                .onOpenURL { url in
                    handle(url)
                }
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme == "cursormobile" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.host == "permission" || parts.first == "permission" {
            let option = url.lastPathComponent
            if option == "yes" { CompanionClient.shared.decidePermission("allow-once") }
            if option == "no" { CompanionClient.shared.decidePermission("reject-once") }
        }
    }
}
