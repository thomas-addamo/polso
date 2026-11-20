import SwiftUI

struct ChatView: View {
    let conversationID: UUID

    @Environment(ConversationStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatService.self) private var chat

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var conversation: Conversation? { store.conversation(conversationID) }

    var body: some View {
        Group {
            if let conversation {
                content(conversation)
            } else {
                ContentUnavailableView("Chat eliminata", systemImage: "trash")
            }
        }
        .navigationTitle(conversation?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let conversation {
                ToolbarItem(placement: .topBarTrailing) { modelMenu(conversation) }
            }
        }
    }

    private func content(_ conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(conversation.messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if chat.isSending(conversationID) {
                        let partial = chat.streamingText[conversationID] ?? ""
                        MessageBubble(message: ChatMessage(role: .assistant, text: partial.isEmpty ? "…" : partial))
                            .id("streaming")
                    }
                    if let error = chat.errors[conversationID] {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                            if conversation.messages.last?.role == .user {
                                Button("Riprova") { Task { await chat.generateReply(for: conversationID) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .id("error")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.messages.count) { scrollToBottom(proxy) }
            .onChange(of: chat.streamingText[conversationID]) { scrollToBottom(proxy, animated: false) }
            .onAppear { scrollToBottom(proxy, animated: false) }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Scrivi a Claude…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($inputFocused)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            Button {
                let text = draft
                draft = ""
                Task { await chat.send(text, to: conversationID) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isSending(conversationID))
            .accessibilityLabel("Invia")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func modelMenu(_ conversation: Conversation) -> some View {
        Menu {
            Picker("Modello", selection: Binding(
                get: { conversation.model },
                set: { newValue in
                    var updated = conversation
                    updated.model = newValue
                    updated.updatedAt = Date()
                    store.upsert(updated)
                }
            )) {
                ForEach(modelOptions(including: conversation.model)) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        } label: {
            Image(systemName: "cpu")
        }
        .accessibilityLabel("Modello")
    }

    private func modelOptions(including current: String) -> [ModelInfo] {
        var list = settings.models
        if !list.contains(where: { $0.id == current }) {
            list.insert(ModelInfo(id: current, displayName: current, supportsEffort: false), at: 0)
        }
        return list
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            MarkdownText(message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .background(
                    message.role == .user ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.thinMaterial),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .opacity(message.isRefusal ? 0.6 : 1)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
