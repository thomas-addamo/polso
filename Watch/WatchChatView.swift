import SwiftUI
import WatchKit

struct WatchChatView: View {
    let conversationID: UUID

    @Environment(ConversationStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatService.self) private var chat

    @State private var draft = ""

    private var conversation: Conversation? { store.conversation(conversationID) }

    var body: some View {
        Group {
            if let conversation {
                content(conversation)
            } else {
                Text("Chat eliminata").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(conversation?.title ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WatchModelPicker(conversationID: conversationID)
                } label: {
                    Image(systemName: "cpu")
                }
                .accessibilityLabel("Modello")
            }
        }
    }

    private func content(_ conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(conversation.messages) { message in
                        WatchBubble(message: message).id(message.id)
                    }

                    if chat.isSending(conversationID) {
                        let partial = chat.streamingText[conversationID] ?? ""
                        if partial.isEmpty {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            WatchBubble(message: ChatMessage(role: .assistant, text: partial))
                        }
                    }

                    if let error = chat.errors[conversationID] {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        if conversation.messages.last?.role == .user {
                            Button("Riprova") { Task { await chat.generateReply(for: conversationID) } }
                        }
                    }

                    // Il campo di testo di watchOS apre dettatura, Scribble e tastiera.
                    TextField("Scrivi…", text: $draft)
                        .disabled(chat.isSending(conversationID))
                        .onSubmit(send)
                        .id("input")
                }
            }
            .onAppear { proxy.scrollTo("input", anchor: .bottom) }
            .onChange(of: conversation.messages.count) { oldCount, newCount in
                withAnimation { proxy.scrollTo("input", anchor: .bottom) }
                if newCount > oldCount, conversation.messages.last?.role == .assistant {
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await chat.send(text, to: conversationID) }
    }
}

private struct WatchBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
            if let attachments = message.attachments {
                ForEach(attachments) { attachment in
                    AttachmentImage(attachment: attachment, contentMode: .fit)
                        .frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            if !message.text.isEmpty {
            MarkdownText(message.text)
                .font(.footnote)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                .background(
                    message.role == .user ? Color.accentColor.opacity(0.35) : Color.gray.opacity(0.2),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .opacity(message.isRefusal ? 0.6 : 1)
            }
            if let cost = message.costUSD {
                Text("≈ \(Pricing.format(cost))")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
    }
}

struct WatchModelPicker: View {
    let conversationID: UUID

    @Environment(ConversationStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if settings.models.isEmpty {
                Text(settings.modelsError ?? "Nessun modello caricato.").font(.footnote)
            }
            ForEach(settings.models) { model in
                Button {
                    guard var conversation = store.conversation(conversationID) else { return }
                    conversation.model = model.id
                    conversation.updatedAt = Date()
                    store.upsert(conversation)
                    dismiss()
                } label: {
                    HStack {
                        Text(model.displayName)
                        Spacer()
                        if store.conversation(conversationID)?.model == model.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Button {
                Task { await settings.refreshModels() }
            } label: {
                Label(settings.isLoadingModels ? "Caricamento…" : "Aggiorna", systemImage: "arrow.clockwise")
            }
        }
        .navigationTitle("Modello")
    }
}
