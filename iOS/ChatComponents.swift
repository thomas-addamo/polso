import SwiftUI
import UIKit

// MARK: - Messaggi

struct UserMessageView: View {
    let message: ChatMessage
    let onImageTap: (Attachment) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let attachments = message.attachments, !attachments.isEmpty {
                AttachmentGrid(attachments: attachments, onTap: onImageTap)
            }
            if !message.text.isEmpty {
                Text(MarkdownText.render(message.text))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(
                        Theme.gradient,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 22, bottomLeadingRadius: 22,
                            bottomTrailingRadius: 6, topTrailingRadius: 22, style: .continuous
                        )
                    )
                    .shadow(color: Theme.accent.opacity(0.25), radius: 10, y: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 52)
        .contextMenu {
            if !message.text.isEmpty {
                Button("Copia", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
            }
        }
    }
}

struct AssistantMessageView: View {
    let message: ChatMessage
    let modelName: String?
    let onRegenerate: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AssistantAvatar(size: 28)
            VStack(alignment: .leading, spacing: 8) {
                MarkdownBlocksView(text: message.text)
                    .opacity(message.isRefusal ? 0.6 : 1)
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copia", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
            ShareLink(item: message.text) { Label("Condividi", systemImage: "square.and.arrow.up") }
            if let onRegenerate {
                Button("Rigenera risposta", systemImage: "arrow.clockwise", action: onRegenerate)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        let parts = [modelName, message.costUSD.map { "≈ \(Pricing.format($0))" }].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct StreamingMessageView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AssistantAvatar(size: 28)
                .phaseAnimator([false, true]) { avatar, pulsing in
                    avatar.scaleEffect(pulsing ? 1.08 : 1)
                } animation: { _ in .easeInOut(duration: 0.8) }
            if text.isEmpty {
                TypingIndicator()
            } else {
                MarkdownBlocksView(text: text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TypingIndicator: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let wave = max(0, sin(t * 5 - Double(i) * 0.8))
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .opacity(0.3 + 0.7 * wave)
                        .offset(y: -3 * wave)
                }
            }
            .padding(.vertical, 10)
        }
        .accessibilityLabel("Claude sta scrivendo")
    }
}

struct AttachmentGrid: View {
    let attachments: [Attachment]
    let onTap: (Attachment) -> Void

    var body: some View {
        if attachments.count == 1, let only = attachments.first {
            AttachmentImage(attachment: only, contentMode: .fit)
                .frame(maxWidth: 240, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture { onTap(only) }
        } else {
            LazyVGrid(columns: [GridItem(.fixed(112), spacing: 6), GridItem(.fixed(112), spacing: 6)], spacing: 6) {
                ForEach(attachments) { attachment in
                    AttachmentImage(attachment: attachment)
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture { onTap(attachment) }
                }
            }
            .frame(width: 230)
        }
    }
}

struct ErrorCard: View {
    let message: String
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.subheadline)
                if let onRetry {
                    Button("Riprova", systemImage: "arrow.clockwise", action: onRetry)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Chat vuota

struct EmptyChatView: View {
    struct Suggestion: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let prompt: String
        var wantsPhoto = false
    }

    let onPick: (Suggestion) -> Void

    private let suggestions = [
        Suggestion(icon: "lightbulb", title: "Spiegami un concetto in parole semplici", prompt: "Spiegami in parole semplici "),
        Suggestion(icon: "text.bubble", title: "Aiutami a scrivere un messaggio", prompt: "Aiutami a scrivere un messaggio per "),
        Suggestion(icon: "fork.knife", title: "Idee veloci per la cena di stasera", prompt: "Dammi 3 idee veloci per la cena di stasera"),
        Suggestion(icon: "camera.viewfinder", title: "Analizza una foto", prompt: "Cosa vedi in questa foto?", wantsPhoto: true),
    ]

    var body: some View {
        VStack(spacing: 22) {
            AssistantAvatar(size: 72)
                .shadow(color: Theme.accent.opacity(0.35), radius: 20, y: 8)
                .phaseAnimator([false, true]) { avatar, up in
                    avatar.offset(y: up ? -4 : 2)
                } animation: { _ in .easeInOut(duration: 2) }

            VStack(spacing: 6) {
                Text("Come posso aiutarti?")
                    .font(.title2.weight(.bold))
                Text("Scrivi un messaggio o allega una foto.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(suggestions) { suggestion in
                    Button { onPick(suggestion) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: suggestion.icon)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24)
                            Text(suggestion.title)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Barra di scrittura

struct ChatInputBar: View {
    @Binding var draft: String
    @Binding var pending: [Attachment]
    var focus: FocusState<Bool>.Binding
    let isSending: Bool
    let onPhotos: () -> Void
    let onCamera: () -> Void
    let onSend: () -> Void

    @Namespace private var glassNamespace

    private var hasContent: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pending.isEmpty
    }
    private var canSend: Bool { hasContent && !isSending }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !pending.isEmpty { thumbnails }
            if #available(iOS 26.0, *) {
                glassRow
            } else {
                legacyRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .animation(.snappy, value: pending)
    }

    // MARK: Liquid Glass (iOS 26+)

    @available(iOS 26.0, *)
    private var glassRow: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                attachMenu
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("attach", in: glassNamespace)

                textField
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                    .glassEffectID("field", in: glassNamespace)

                if isSending {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular.tint(Theme.accent.opacity(0.6)), in: .circle)
                        .glassEffectID("send", in: glassNamespace)
                } else if canSend {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(Theme.accent).interactive(), in: .circle)
                    .glassEffectID("send", in: glassNamespace)
                    .accessibilityLabel("Invia")
                }
            }
        }
        .animation(.bouncy(duration: 0.4, extraBounce: 0.1), value: canSend)
        .animation(.bouncy(duration: 0.4), value: isSending)
    }

    // MARK: Versioni precedenti di iOS

    private var legacyRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            attachMenu
                .background(Theme.accent.opacity(0.12), in: Circle())
            textField.padding(.vertical, 12)
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        canSend ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.gray.opacity(0.35)),
                        in: Circle()
                    )
            }
            .disabled(!canSend)
            .padding(4)
            .accessibilityLabel("Invia")
        }
        .padding(.leading, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: Parti comuni

    private var textField: some View {
        TextField("Scrivi a Claude…", text: $draft, axis: .vertical)
            .lineLimit(1...6)
            .focused(focus)
            .submitLabel(.return)
    }

    private var attachMenu: some View {
        Menu {
            Button("Libreria foto", systemImage: "photo.on.rectangle", action: onPhotos)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Scatta una foto", systemImage: "camera", action: onCamera)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(pending.count >= 4 ? Color.secondary : Theme.accent)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .disabled(pending.count >= 4)
        .accessibilityLabel("Allega immagine")
    }

    private var thumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pending) { attachment in
                    AttachmentImage(attachment: attachment)
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.25)))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.snappy) { pending.removeAll { $0.id == attachment.id } }
                                ImageStore.shared.delete(attachment.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .font(.system(size: 21))
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Rimuovi immagine")
                        }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
    }
}

/// Pulsante principale: Liquid Glass "prominente" su iOS 26+, gradiente sulle versioni precedenti.
struct ProminentActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .controlSize(.large)
        } else {
            content
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.gradient, in: Capsule())
        }
    }
}

// MARK: - Visualizzatore immagini e fotocamera

struct ImageViewer: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AttachmentImage(attachment: attachment, contentMode: .fit)
                .scaleEffect(scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = max(1, $0.magnification) }
                        .onEnded { _ in withAnimation(.spring) { scale = 1 } }
                )
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
            .accessibilityLabel("Chiudi")
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

enum ImageProcessing {
    /// Ridimensiona (max 1568 px per lato e ~1,15 megapixel, come consigliato per Claude) e comprime in JPEG.
    static func prepare(_ image: UIImage) -> Data? {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width > 0, height > 0 else { return nil }
        let factor = min(1, 1568 / max(width, height), (1_150_000 / (width * height)).squareRoot())
        let target = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
