import SwiftUI
import WatchKit

struct WatchChatView: View {
    let conversationID: UUID

    @Environment(ConversationStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatService.self) private var chat

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
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    modelChip(conversation)

                    ForEach(conversation.messages) { message in
                        WatchMessageView(message: message).id(message.id)
                    }

                    if chat.isSending(conversationID) {
                        let partial = chat.streamingText[conversationID] ?? ""
                        if partial.isEmpty {
                            HStack(spacing: 6) {
                                AssistantAvatar(size: 18)
                                WatchTypingIndicator()
                                Spacer()
                            }
                        } else {
                            WatchMessageView(message: ChatMessage(role: .assistant, text: partial))
                        }
                    }

                    if let error = chat.errors[conversationID] {
                        VStack(spacing: 6) {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                            if conversation.messages.last?.role == .user {
                                Button("Riprova", systemImage: "arrow.clockwise") {
                                    Task { await chat.generateReply(for: conversationID) }
                                }
                                .tint(Theme.accent)
                            }
                        }
                    }

                    replyButton
                        .padding(.top, 4)
                        .id("bottom")
                }
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: conversation.messages.count) { oldCount, newCount in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                if newCount > oldCount, conversation.messages.last?.role == .assistant {
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        }
    }

    /// Modello della chat: tocca per cambiarlo.
    private func modelChip(_ conversation: Conversation) -> some View {
        NavigationLink {
            WatchModelPicker(conversationID: conversationID)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: conversation.providerID.icon)
                Text(settings.displayName(for: conversation.model))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.accentLight)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accent.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Modello: \(settings.displayName(for: conversation.model))")
    }

    /// Apre dettatura, Scribble e tastiera di watchOS.
    private var replyButton: some View {
        TextFieldLink(prompt: Text("Scrivi a Claude")) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                Text("Rispondi")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .modifier(WatchGlassCapsule(prominent: true))
        } onSubmit: { text in
            Task { await chat.send(text, to: conversationID) }
        }
        .buttonStyle(.plain)
        .disabled(chat.isSending(conversationID))
        .opacity(chat.isSending(conversationID) ? 0.5 : 1)
    }
}

// MARK: - Messaggio

private struct WatchMessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(message.attachments ?? []) { attachment in
                    AttachmentImage(attachment: attachment, contentMode: .fit)
                        .frame(maxHeight: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !message.text.isEmpty {
                    MarkdownText(message.text)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Theme.gradient,
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 16, bottomLeadingRadius: 16,
                                bottomTrailingRadius: 4, topTrailingRadius: 16, style: .continuous
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 18)

        case .assistant:
            VStack(alignment: .leading, spacing: 5) {
                AssistantAvatar(size: 18)
                MarkdownText(message.text)
                    .font(.footnote)
                    .opacity(message.isRefusal ? 0.6 : 1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.white.opacity(0.1),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 4, bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous
                )
            )
        }
    }
}

private struct WatchTypingIndicator: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.accentLight)
                        .frame(width: 6, height: 6)
                        .opacity(0.3 + 0.7 * max(0, sin(t * 5 - Double(i) * 0.8)))
                }
            }
        }
        .accessibilityLabel("Claude sta scrivendo")
    }
}

/// Capsula in Liquid Glass su watchOS 26+, gradiente sulle versioni precedenti.
struct WatchGlassCapsule: ViewModifier {
    var prominent = false

    func body(content: Content) -> some View {
        if #available(watchOS 26.0, *) {
            content.glassEffect(
                prominent ? .regular.tint(Theme.accent).interactive() : .regular.interactive(),
                in: .capsule
            )
        } else {
            content.background(
                prominent ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white.opacity(0.12)),
                in: Capsule()
            )
        }
    }
}

// MARK: - Scelta del modello

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
            ForEach(settings.configuredProviders) { provider in
                Section(provider.name) {
                    ForEach(settings.models(for: provider), id: \.key) { model in
                        Button {
                            guard var conversation = store.conversation(conversationID) else { return }
                            conversation.model = model.id
                            conversation.provider = model.provider
                            conversation.updatedAt = Date()
                            store.upsert(conversation)
                            dismiss()
                        } label: {
                            HStack {
                                Text(settings.displayName(for: model.id))
                                Spacer()
                                if let current = store.conversation(conversationID),
                                   current.model == model.id, current.providerID == model.provider {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
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
