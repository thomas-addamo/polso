import SwiftUI
import UIKit

/// Schermata principale: la chat a tutto schermo, con il menu delle chat che si apre di lato.
struct RootView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    @State private var selectedID: UUID?
    @State private var menuOpen = false
    @State private var dragOffset: CGFloat = 0
    @State private var showSettings = false

    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var body: some View {
        GeometryReader { geo in
            let menuWidth = min(geo.size.width * 0.82, 340)
            let progress = openProgress(menuWidth: menuWidth)

            ZStack(alignment: .leading) {
                Theme.sidebarBackground.ignoresSafeArea()

                SidebarView(
                    selectedID: selectedID,
                    onSelect: select,
                    onNewChat: { select(newChat()) },
                    onSettings: { showSettings = true }
                )
                .frame(width: menuWidth)
                .opacity(0.3 + 0.7 * progress)
                .offset(x: -40 * (1 - progress))

                mainContent
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 44 * progress, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 44 * progress, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08 * progress))
                    }
                    .shadow(color: .black.opacity(0.25 * progress), radius: 24)
                    .overlay {
                        if menuOpen {
                            Color.black.opacity(0.001)
                                .onTapGesture { setMenu(false) }
                        }
                    }
                    .offset(x: menuWidth * progress)
            }
            .simultaneousGesture(dragGesture(menuWidth: menuWidth))
        }
        .ignoresSafeArea()
        .onAppear(perform: selectInitialChat)
        .onChange(of: store.conversations.map(\.id)) {
            // La chat aperta è stata eliminata (anche dal Watch): ne apre un'altra.
            if let selectedID, store.conversation(selectedID) == nil { selectInitialChat() }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    @ViewBuilder
    private var mainContent: some View {
        NavigationStack {
            if let selectedID {
                ChatView(
                    conversationID: selectedID,
                    onMenu: { setMenu(true) },
                    onNewChat: { select(newChat()) },
                    onSettings: { showSettings = true }
                )
                .id(selectedID)
            } else {
                Theme.background.ignoresSafeArea()
            }
        }
    }

    // MARK: Apertura del menu

    private func openProgress(menuWidth: CGFloat) -> CGFloat {
        let base: CGFloat = menuOpen ? 1 : 0
        return min(1, max(0, base + dragOffset / menuWidth))
    }

    private func dragGesture(menuWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) else { return }
                if menuOpen {
                    dragOffset = min(0, dx)
                } else if value.startLocation.x < 60 {
                    // Da chiuso il menu si apre trascinando dal bordo sinistro.
                    dragOffset = max(0, dx)
                }
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width
                let wasDragging = dragOffset != 0
                withAnimation(spring) {
                    if menuOpen, predicted < -menuWidth / 3 {
                        menuOpen = false
                    } else if !menuOpen, wasDragging, predicted > menuWidth / 3 {
                        menuOpen = true
                        dismissKeyboard()
                    }
                    dragOffset = 0
                }
            }
    }

    private func setMenu(_ open: Bool) {
        if open { dismissKeyboard() }
        withAnimation(spring) { menuOpen = open }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: Selezione delle chat

    private func select(_ id: UUID) {
        selectedID = id
        setMenu(false)
    }

    private func selectInitialChat() {
        selectedID = store.visibleConversations.first?.id ?? newChat()
    }

    /// Riusa una chat vuota se c'è, altrimenti ne crea una con il modello predefinito.
    private func newChat() -> UUID {
        if var empty = store.conversations.first(where: { $0.messages.isEmpty }) {
            if empty.model != settings.defaultModel || empty.providerID != settings.defaultProvider {
                empty.model = settings.defaultModel
                empty.provider = settings.defaultProvider
                store.upsert(empty)
            }
            return empty.id
        }
        return store.create(model: settings.defaultModel, provider: settings.defaultProvider).id
    }
}

// MARK: - Menu laterale

struct SidebarView: View {
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onNewChat: () -> Void
    let onSettings: () -> Void

    @Environment(ConversationStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var renaming: Conversation?
    @State private var newTitle = ""
    @State private var deleting: Conversation?

    private var chats: [Conversation] {
        let list = store.visibleConversations
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if searching {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Cerca nelle chat", text: $query)
                        .focused($searchFocused)
                        .submitLabel(.search)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .modifier(GlassCapsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let pinned = chats.filter(\.isPinned)
                    if !pinned.isEmpty {
                        sectionTitle("Fissate")
                        ForEach(pinned) { chatRow($0) }
                    }

                    sectionTitle("Recenti").padding(.top, pinned.isEmpty ? 0 : 10)

                    if chats.isEmpty {
                        Text(query.isEmpty ? "Le tue chat compariranno qui." : "Nessun risultato.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                    }

                    ForEach(chats.filter { !$0.isPinned }) { conversation in
                        chatRow(conversation)
                    }

                    sectionTitle("Altro").padding(.top, 14)

                    menuRow(icon: "chart.bar", title: "Spesa del mese", trailing: "≈ \(Pricing.format(store.spendingThisMonth))") {}
                        .allowsHitTesting(false)
                    menuRow(icon: "key", title: "Provider e chiavi API", action: onSettings)
                    menuRow(icon: "gearshape", title: "Impostazioni", action: onSettings)
                }
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 60)
        .overlay(alignment: .bottom) { bottomBar }
        .animation(.snappy, value: searching)
        .animation(.snappy, value: store.visibleConversations.map(\.id))
        .alert("Rinomina chat", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Titolo", text: $newTitle)
            Button("Annulla", role: .cancel) { renaming = nil }
            Button("Salva") {
                if let renaming { store.rename(renaming.id, to: newTitle) }
                renaming = nil
            }
        }
        .confirmationDialog(
            "Eliminare questa chat?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { conversation in
            Button("Elimina chat", role: .destructive) {
                withAnimation { store.delete(conversation.id) }
                deleting = nil
            }
        } message: { conversation in
            Text("«\(conversation.title)» verrà eliminata anche dall'Apple Watch. L'operazione non si può annullare.")
        }
    }

    private var header: some View {
        HStack {
            Text("Polso")
                .font(.system(size: 34, weight: .semibold, design: .serif))
            Spacer()
            Button {
                searching.toggle()
                if searching { searchFocused = true } else { query = "" }
            } label: {
                Image(systemName: searching ? "xmark" : "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 46, height: 46)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .modifier(GlassCircle())
            .accessibilityLabel(searching ? "Chiudi ricerca" : "Cerca")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 6)
    }

    private func chatRow(_ conversation: Conversation) -> some View {
        let selected = conversation.id == selectedID
        return HStack(spacing: 0) {
            Button { onSelect(conversation.id) } label: {
                HStack(spacing: 14) {
                    Image(systemName: conversation.providerID == .anthropic ? "bubble.left" : conversation.providerID.icon)
                        .font(.system(size: 17))
                        .foregroundStyle(selected ? Theme.accent : .secondary)
                        .frame(width: 24)
                    Text(conversation.title)
                        .font(.body)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Rinomina", systemImage: "pencil") {
                    newTitle = conversation.title
                    renaming = conversation
                }
                Button(conversation.isPinned ? "Rimuovi dalle fissate" : "Fissa in alto",
                       systemImage: conversation.isPinned ? "pin.slash" : "pin") {
                    store.togglePin(conversation.id)
                }
                ShareLink(item: conversation.transcript, subject: Text(conversation.title)) {
                    Label("Condividi", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button("Elimina", systemImage: "trash", role: .destructive) {
                    deleting = conversation
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .tint(.secondary)
            .accessibilityLabel("Opzioni per \(conversation.title)")
        }
        .padding(.trailing, 2)
        .background(
            selected ? Color.primary.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .padding(.horizontal, 8)
    }

    private func menuRow(icon: String, title: String, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(title)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Button(action: onSettings) {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .modifier(GlassCircle())
            .accessibilityLabel("Impostazioni")

            Spacer(minLength: 0)

            Button(action: onNewChat) {
                Label("Nuova chat", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 16)
                    .background(Color.primary, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 34)
    }
}

// MARK: - Vetro

/// Liquid Glass su iOS 26+, materiale sulle versioni precedenti.
struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(.regularMaterial, in: Circle())
        }
    }
}

struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
