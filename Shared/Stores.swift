import Foundation
import Observation

// MARK: - Conversazioni

@Observable @MainActor
final class ConversationStore {
    private struct Persisted: Codable {
        var conversations: [Conversation]
        var deleted: Set<UUID>
        var spending: [UUID: SpendEntry]?
    }

    private(set) var conversations: [Conversation] = []
    private var deleted: Set<UUID> = []
    /// Registro delle spese per messaggio: resta anche se la chat viene eliminata.
    private(set) var spending: [UUID: SpendEntry] = [:]

    /// Spesa stimata del mese corrente (somma di iPhone e Watch, grazie alla sincronizzazione).
    var spendingThisMonth: Double {
        spending.values
            .filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.cost }
    }

    /// Chiamati per le modifiche locali, per inviarle all'altro dispositivo.
    @ObservationIgnored var onUpsert: ((Conversation) -> Void)?
    @ObservationIgnored var onDelete: ((UUID) -> Void)?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversations.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let state = try? JSONDecoder().decode(Persisted.self, from: data) {
            conversations = state.conversations.sorted { $0.updatedAt > $1.updatedAt }
            deleted = state.deleted
            spending = state.spending ?? [:]
            conversations.forEach(recordSpending)
        }
    }

    func conversation(_ id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func create(model: String) -> Conversation {
        let conversation = Conversation(model: model)
        upsert(conversation)
        return conversation
    }

    func upsert(_ conversation: Conversation) {
        apply(conversation)
        save()
        onUpsert?(conversation)
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        deleted.insert(id)
        save()
        onDelete?(id)
    }

    // MARK: Sincronizzazione

    /// Applica una conversazione ricevuta dall'altro dispositivo (vince la più recente).
    func mergeRemote(_ remote: Conversation) {
        guard !deleted.contains(remote.id) else { return }
        if let local = conversation(remote.id), local.updatedAt >= remote.updatedAt { return }
        apply(remote)
        save()
    }

    func applyRemoteDelete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        deleted.insert(id)
        save()
    }

    func exportState() throws -> Data {
        try JSONEncoder().encode(Persisted(conversations: conversations, deleted: deleted, spending: spending))
    }

    func importState(_ data: Data) {
        guard let state = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        spending.merge(state.spending ?? [:]) { local, _ in local }
        state.deleted.forEach(applyRemoteDelete)
        state.conversations.forEach(mergeRemote)
        save()
    }

    private func recordSpending(_ conversation: Conversation) {
        for message in conversation.messages where message.role == .assistant {
            if let cost = message.costUSD, spending[message.id] == nil {
                spending[message.id] = SpendEntry(date: message.createdAt, cost: cost)
            }
        }
    }

    private func apply(_ conversation: Conversation) {
        recordSpending(conversation)
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        guard let data = try? exportState() else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - Impostazioni

@Observable @MainActor
final class SettingsStore {
    private static let keyAccount = "anthropic-api-key"
    private let defaults = UserDefaults.standard

    private(set) var apiKey: String?
    private(set) var models: [ModelInfo] = []
    var isLoadingModels = false
    var modelsError: String?

    var defaultModel: String {
        didSet { defaults.set(defaultModel, forKey: "defaultModel"); notify() }
    }
    var effort: Effort {
        didSet { defaults.set(effort.rawValue, forKey: "effort"); notify() }
    }

    /// Solo su iPhone: invia le impostazioni al Watch quando cambiano.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var suppressNotify = false

    init() {
        apiKey = Keychain.get(Self.keyAccount)
        // Migrazione una tantum: chi aveva ancora Opus come predefinito passa a Sonnet (più economico).
        if !defaults.bool(forKey: "migratedDefaultToSonnet") {
            if defaults.string(forKey: "defaultModel") == "claude-opus-5-5" {
                defaults.removeObject(forKey: "defaultModel")
            }
            defaults.set(true, forKey: "migratedDefaultToSonnet")
        }
        defaultModel = defaults.string(forKey: "defaultModel") ?? AppConstants.defaultModel
        effort = Effort(rawValue: defaults.string(forKey: "effort") ?? "") ?? .low
        if let data = defaults.data(forKey: "models"),
           let cached = try? JSONDecoder().decode([ModelInfo].self, from: data) {
            models = cached
        }
    }

    var hasAPIKey: Bool { !(apiKey ?? "").isEmpty }

    func setAPIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        Keychain.set(value, for: Self.keyAccount)
        apiKey = value
        notify()
    }

    /// Impostazioni ricevute dall'iPhone (sul Watch).
    func applyRemote(apiKey: String?, defaultModel: String?, effort: String?) {
        suppressNotify = true
        defer { suppressNotify = false }
        if let apiKey { setAPIKey(apiKey) }
        if let defaultModel, !defaultModel.isEmpty { self.defaultModel = defaultModel }
        if let effort, let value = Effort(rawValue: effort) { self.effort = value }
    }

    func refreshModels() async {
        guard let apiKey, !apiKey.isEmpty else { return }
        isLoadingModels = true
        modelsError = nil
        defer { isLoadingModels = false }
        do {
            models = try await AnthropicClient(apiKey: apiKey).listModels()
            defaults.set(try? JSONEncoder().encode(models), forKey: "models")
        } catch {
            modelsError = error.localizedDescription
        }
    }

    func displayName(for modelID: String) -> String {
        models.first { $0.id == modelID }?.displayName ?? modelID
    }

    /// L'effort si invia solo ai modelli che lo supportano.
    func effortParameter(for modelID: String) -> Effort? {
        models.first { $0.id == modelID }?.supportsEffort == true ? effort : nil
    }

    private func notify() {
        if !suppressNotify { onChange?() }
    }
}

// MARK: - Invio messaggi

@Observable @MainActor
final class ChatService {
    private(set) var streamingText: [UUID: String] = [:]
    private(set) var sending: Set<UUID> = []
    var errors: [UUID: String] = [:]

    private let store: ConversationStore
    private let settings: SettingsStore

    init(store: ConversationStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    func isSending(_ id: UUID) -> Bool { sending.contains(id) }

    func send(_ text: String, to id: UUID) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending.contains(id), var conversation = store.conversation(id) else { return }
        conversation.messages.append(ChatMessage(role: .user, text: trimmed))
        if conversation.title == Conversation.untitled {
            conversation.title = String(trimmed.prefix(60))
        }
        conversation.updatedAt = Date()
        store.upsert(conversation)
        await generateReply(for: id)
    }

    /// Chiede una risposta per l'ultimo messaggio dell'utente (usato anche per "Riprova").
    func generateReply(for id: UUID) async {
        guard let conversation = store.conversation(id), !sending.contains(id) else { return }
        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            errors[id] = "Manca la chiave API. Inseriscila nelle impostazioni dell'app sull'iPhone."
            return
        }

        sending.insert(id)
        errors[id] = nil
        streamingText[id] = ""
        defer {
            sending.remove(id)
            streamingText[id] = nil
        }

        let client = AnthropicClient(apiKey: apiKey)
        let effort = settings.effortParameter(for: conversation.model)
        let onText: @MainActor (String) -> Void = { [weak self] delta in
            self?.streamingText[id, default: ""] += delta
        }

        do {
            let result: StreamResult
            do {
                result = try await client.streamMessage(
                    model: conversation.model,
                    messages: PayloadBuilder.messages(for: conversation, stripThinking: false),
                    effort: effort,
                    onText: onText
                )
            } catch let error as AnthropicAPIError where error.status == 400 && PayloadBuilder.hasThinking(conversation) {
                // Recupero una tantum: se la cronologia non è più valida per i thinking block
                // (es. cambio di modello), si riprova senza blocchi di ragionamento.
                streamingText[id] = ""
                result = try await client.streamMessage(
                    model: conversation.model,
                    messages: PayloadBuilder.messages(for: conversation, stripThinking: true),
                    effort: effort,
                    onText: onText
                )
            }

            let refused = result.stopReason == "refusal"
            var text = result.text
            if text.isEmpty { text = refused ? "La richiesta è stata rifiutata." : "(risposta vuota)" }
            if result.stopReason == "max_tokens" { text += "\n\n_(risposta troncata)_" }

            let servedModel = result.model ?? conversation.model
            var latest = store.conversation(id) ?? conversation
            latest.messages.append(ChatMessage(
                role: .assistant,
                text: text,
                model: servedModel,
                rawContent: refused ? nil : result.content,
                isRefusal: refused,
                usage: result.usage,
                costUSD: Pricing.cost(model: servedModel, usage: result.usage)
            ))
            latest.updatedAt = Date()
            store.upsert(latest)
        } catch is CancellationError {
            errors[id] = "Richiesta annullata."
        } catch {
            errors[id] = error.localizedDescription
        }
    }
}
