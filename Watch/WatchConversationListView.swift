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
                        icon: "iphone",
                        title: "Configura Polso",
                        text: "Apri l'app sull'iPhone e inserisci la chiave API."
                    )
                } else if store.conversations.isEmpty {
                    placeholder(
                        icon: "bubble.left.and.bubble.right",
                        title: "Nessuna chat",
                        text: "Crea una chat sull'iPhone: comparirà qui."
                    )
                } else {
                    List {
                        ForEach(store.conversations) { conversation in
                            NavigationLink(value: conversation.id) {
                                row(conversation)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.fill")
                                .foregroundStyle(Theme.accentLight)
                            Text("Questo mese")
                            Spacer()
                            Text("≈ \(Pricing.format(store.spendingThisMonth))")
                                .fontWeight(.semibold)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Polso")
            .navigationDestination(for: UUID.self) { id in
                WatchChatView(conversationID: id)
            }
        }
    }

    private func row(_ conversation: Conversation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AssistantAvatar(size: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 3) {
                    if conversation.messages.last?.hasAttachments == true {
                        Image(systemName: "photo")
                    }
                    Text(conversation.preview).lineLimit(2)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text(conversation.updatedAt.shortRelative)
                    .font(.caption2)
                    .foregroundStyle(Theme.accentLight)
            }
        }
        .padding(.vertical, 4)
    }

    private func placeholder(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.gradient, in: Circle())
            Text(title).font(.headline)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
