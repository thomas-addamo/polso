import PhotosUI
import SwiftUI

struct ChatView: View {
    let conversationID: UUID

    @Environment(ConversationStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatService.self) private var chat

    @State private var draft = ""
    @State private var pending: [Attachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var viewerAttachment: Attachment?
    @State private var sendCount = 0
    @FocusState private var inputFocused: Bool

    private var conversation: Conversation? { store.conversation(conversationID) }
    private var lastAssistantID: UUID? { conversation?.messages.last { $0.role == .assistant }?.id }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let conversation {
                content(conversation)
            } else {
                ContentUnavailableView("Chat eliminata", systemImage: "trash")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if let conversation {
                ToolbarItem(placement: .principal) { titleMenu(conversation) }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 4 - pending.count, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { addImage($0) }.ignoresSafeArea()
        }
        .fullScreenCover(item: $viewerAttachment) { ImageViewer(attachment: $0) }
        .sensoryFeedback(.impact(weight: .light), trigger: sendCount)
        .sensoryFeedback(.success, trigger: lastAssistantID)
    }

    // MARK: Contenuto

    private func content(_ conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
                    if conversation.messages.isEmpty && !chat.isSending(conversationID) {
                        EmptyChatView { suggestion in
                            draft = suggestion.prompt
                            if suggestion.wantsPhoto { showPhotos = true } else { inputFocused = true }
                        }
                        .padding(.top, 40)
                    }

                    ForEach(conversation.messages) { message in
                        row(for: message, in: conversation)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if chat.isSending(conversationID) {
                        StreamingMessageView(text: chat.streamingText[conversationID] ?? "")
                            .transition(.opacity)
                    }

                    if let error = chat.errors[conversationID] {
                        ErrorCard(
                            message: error,
                            onRetry: conversation.messages.last?.role == .user
                                ? { Task { await chat.generateReply(for: conversationID) } }
                                : nil
                        )
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .animation(.spring(duration: 0.4), value: conversation.messages.count)
                .animation(.easeOut(duration: 0.2), value: chat.isSending(conversationID))
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: chat.streamingText[conversationID]) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .safeAreaInset(edge: .bottom) {
                ChatInputBar(
                    draft: $draft,
                    pending: $pending,
                    focus: $inputFocused,
                    isSending: chat.isSending(conversationID),
                    onPhotos: { showPhotos = true },
                    onCamera: { showCamera = true },
                    onSend: send
                )
            }
        }
    }

    @ViewBuilder
    private func row(for message: ChatMessage, in conversation: Conversation) -> some View {
        switch message.role {
        case .user:
            UserMessageView(message: message) { viewerAttachment = $0 }
        case .assistant:
            let isLast = message.id == conversation.messages.last?.id
            AssistantMessageView(
                message: message,
                modelName: message.model.map(settings.displayName(for:)),
                onRegenerate: isLast && !chat.isSending(conversationID)
                    ? { Task { await chat.regenerate(conversationID) } }
                    : nil
            )
        }
    }

    // MARK: Titolo e modello

    private func titleMenu(_ conversation: Conversation) -> some View {
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
            VStack(spacing: 1) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Text(settings.displayName(for: conversation.model))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: 240)
        }
        .tint(.primary)
        .accessibilityLabel("Modello: \(settings.displayName(for: conversation.model))")
    }

    private func modelOptions(including current: String) -> [ModelInfo] {
        var list = settings.models
        if !list.contains(where: { $0.id == current }) {
            list.insert(ModelInfo(id: current, displayName: current, supportsEffort: false), at: 0)
        }
        return list
    }

    // MARK: Azioni

    private func send() {
        let text = draft
        let attachments = pending
        draft = ""
        pending = []
        sendCount += 1
        Task { await chat.send(text, attachments: attachments, to: conversationID) }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                addImage(image)
            }
        }
        photoItems = []
    }

    private func addImage(_ image: UIImage) {
        guard pending.count < 4, let jpeg = ImageProcessing.prepare(image) else { return }
        withAnimation(.snappy) { pending.append(ImageStore.shared.save(jpeg)) }
    }
}
