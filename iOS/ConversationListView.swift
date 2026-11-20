import SwiftUI

struct ConversationListView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    @State private var path: [UUID] = []
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !settings.hasAPIKey {
                    Section {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Inserisci la tua chiave API Anthropic per iniziare", systemImage: "key.fill")
                        }
                    }
                }

                ForEach(store.conversations) { conversation in
                    NavigationLink(value: conversation.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conversation.title).font(.headline).lineLimit(1)
                                Spacer()
                                Text(conversation.updatedAt.shortRelative)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(conversation.preview)
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            Text(settings.displayName(for: conversation.model))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { offsets in
                    offsets.map { store.conversations[$0].id }.forEach(store.delete)
                }

                if settings.hasAPIKey {
                    Section {
                        LabeledContent("Spesa di questo mese", value: "≈ \(Pricing.format(store.spendingThisMonth))")
                    } footer: {
                        Text("Stima calcolata dai token di ogni risposta, inclusi quelli inviati dal Watch. L'importo esatto è nella Console di Anthropic.")
                    }
                }
            }
            .overlay {
                if store.conversations.isEmpty && settings.hasAPIKey {
                    ContentUnavailableView(
                        "Nessuna chat",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Crea una chat qui: la ritroverai anche sull'Apple Watch.")
                    )
                }
            }
            .navigationTitle("Polso")
            .navigationDestination(for: UUID.self) { id in
                ChatView(conversationID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Impostazioni")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let conversation = store.create(model: settings.defaultModel)
                        path.append(conversation.id)
                    } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Nuova chat")
                        .disabled(!settings.hasAPIKey)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}
