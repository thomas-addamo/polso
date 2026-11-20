import SwiftUI

/// Sul Watch si vedono solo le chat già esistenti (create sull'iPhone).
struct WatchConversationListView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            Group {
                if !settings.hasAPIKey {
                    placeholder(
                        icon: "iphone.and.arrow.forward",
                        text: "Apri Polso sull'iPhone e inserisci la chiave API."
                    )
                } else if store.conversations.isEmpty {
                    placeholder(
                        icon: "bubble.left.and.bubble.right",
                        text: "Nessuna chat. Creane una sull'iPhone."
                    )
                } else {
                    List(store.conversations) { conversation in
                        NavigationLink(value: conversation.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conversation.title).font(.headline).lineLimit(2)
                                Text(conversation.preview)
                                    .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                Text(conversation.updatedAt.shortRelative)
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Polso")
            .navigationDestination(for: UUID.self) { id in
                WatchChatView(conversationID: id)
            }
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(text).font(.footnote).multilineTextAlignment(.center)
        }
        .padding()
    }
}
