import SwiftUI

@main
struct PeridotApp: App {
    @State private var store = ChatStore()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.mint)
        }
    }
}
