import SwiftUI

struct ConversationListView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    @State private var path: [UUID] = []
    @State private var showSettings = false
    @State private var query = ""

    private var filtered: [Conversation] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.conversations }
        return store.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !settings.hasAPIKey {
                    Section {
                        Button { showSettings = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.gradient, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Collega la tua chiave API").font(.headline)
                                    Text("Serve per parlare con Claude").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .listRowBackground(Theme.surface)
                } else if query.isEmpty {
                    Section {
                        SpendingCard(total: store.spendingThisMonth)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                if !filtered.isEmpty {
                    Section(query.isEmpty ? "Chat" : "Risultati") {
                        ForEach(filtered) { conversation in
                            NavigationLink(value: conversation.id) {
                                ConversationRow(
                                    conversation: conversation,
                                    modelName: settings.displayName(for: conversation.model)
                                )
                            }
                            .listRowBackground(Theme.surface)
                        }
                        .onDelete { offsets in
                            offsets.map { filtered[$0].id }.forEach(store.delete)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $query, prompt: "Cerca nelle chat")
            .overlay {
                if store.conversations.isEmpty && settings.hasAPIKey {
                    VStack(spacing: 14) {
                        AssistantAvatar(size: 64)
                        Text("Nessuna chat").font(.title3.weight(.semibold))
                        Text("Inizia una conversazione: la ritroverai anche sull'Apple Watch.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else if !query.isEmpty && filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Polso")
            .navigationDestination(for: UUID.self) { id in
                ChatView(conversationID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Impostazioni")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if settings.hasAPIKey {
                    Button {
                        let conversation = store.create(model: settings.defaultModel)
                        path.append(conversation.id)
                    } label: {
                        Label("Nuova chat", systemImage: "square.and.pencil")
                            .font(.headline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .modifier(ProminentActionStyle())
                    .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let modelName: String

    var body: some View {
        HStack(spacing: 12) {
            AssistantAvatar(size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(conversation.updatedAt.shortRelative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if conversation.messages.last?.hasAttachments == true {
                        Image(systemName: "photo").font(.caption)
                    }
                    Text(conversation.preview).lineLimit(2)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(modelName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SpendingCard: View {
    let total: Double

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Spesa di questo mese")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("≈ \(Pricing.format(total))")
                    .font(.title2.weight(.bold))
                    .contentTransition(.numericText())
            }
            Spacer()
            Text("iPhone + Watch")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}
