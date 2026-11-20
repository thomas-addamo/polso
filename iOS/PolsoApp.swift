import SwiftUI

@main
struct PolsoApp: App {
    @State private var store: ConversationStore
    @State private var settings: SettingsStore
    @State private var chat: ChatService

    init() {
        let store = ConversationStore()
        let settings = SettingsStore()
        _store = State(initialValue: store)
        _settings = State(initialValue: settings)
        _chat = State(initialValue: ChatService(store: store, settings: settings))
        SyncManager.shared.start(store: store, settings: settings)
    }

    var body: some Scene {
        WindowGroup {
            ConversationListView()
                .environment(store)
                .environment(settings)
                .environment(chat)
                .tint(Theme.accent)
                .task { await settings.refreshModels() }
        }
    }
}
