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

    func create(model: String, provider: ProviderID) -> Conversation {
        let conversation = Conversation(model: model, provider: provider)
        upsert(conversation)
        return conversation
    }

    /// Chat con almeno un messaggio (quelle vuote non compaiono negli elenchi).
    var visibleConversations: [Conversation] {
        conversations.filter { !$0.messages.isEmpty }
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
    private let defaults = UserDefaults.standard

    private(set) var apiKeys: [ProviderID: String] = [:]
    private(set) var models: [ModelInfo] = []
    var isLoadingModels = false
    var modelsError: String?

    var defaultModel: String {
        didSet { defaults.set(defaultModel, forKey: "defaultModel"); notify() }
    }
    var defaultProvider: ProviderID {
        didSet { defaults.set(defaultProvider.rawValue, forKey: "defaultProvider"); notify() }
    }
    var effort: Effort {
        didSet { defaults.set(effort.rawValue, forKey: "effort"); notify() }
    }

    /// Solo su iPhone: invia le impostazioni al Watch quando cambiano.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var suppressNotify = false

    init() {
        // Migrazione una tantum: chi aveva ancora Opus come predefinito passa a Sonnet (più economico).
        if !defaults.bool(forKey: "migratedDefaultToSonnet") {
            if defaults.string(forKey: "defaultModel") == "claude-opus-5-5" {
                defaults.removeObject(forKey: "defaultModel")
            }
            defaults.set(true, forKey: "migratedDefaultToSonnet")
        }
        defaultModel = defaults.string(forKey: "defaultModel") ?? AppConstants.defaultModel
        defaultProvider = ProviderID(rawValue: defaults.string(forKey: "defaultProvider") ?? "") ?? .anthropic
        effort = Effort(rawValue: defaults.string(forKey: "effort") ?? "") ?? .low
        if let data = defaults.data(forKey: "models"),
           let cached = try? JSONDecoder().decode([ModelInfo].self, from: data) {
            models = cached
        }
        var keys: [ProviderID: String] = [:]
        for provider in ProviderID.allCases {
            if let key = Keychain.get(provider.keychainAccount), !key.isEmpty { keys[provider] = key }
        }
        apiKeys = keys
    }

    // MARK: Chiavi

    /// Chiave Anthropic (compatibilità con il codice precedente).
    var apiKey: String? { apiKeys[.anthropic] }
    var hasAPIKey: Bool { !apiKeys.isEmpty }
    var configuredProviders: [ProviderID] { ProviderID.allCases.filter { apiKeys[$0] != nil } }

    func apiKey(for provider: ProviderID) -> String? { apiKeys[provider] }

    func setAPIKey(_ key: String?, for provider: ProviderID = .anthropic) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        Keychain.set(value, for: provider.keychainAccount)
        apiKeys[provider] = value
        if value == nil {
            models.removeAll { $0.provider == provider }
            saveModels()
            // Se il predefinito era di questo provider, passa al primo provider disponibile.
            if defaultProvider == provider, let other = models.first {
                defaultProvider = other.provider
                defaultModel = other.id
            }
        }
        notify()
    }

    /// Impostazioni ricevute dall'iPhone (sul Watch).
    func applyRemote(keys: [String: String], defaultModel: String?, defaultProvider: String?, effort: String?) {
        suppressNotify = true
        defer { suppressNotify = false }
        for provider in ProviderID.allCases {
            let remote = keys[provider.rawValue]
            if remote != apiKeys[provider] { setAPIKey(remote, for: provider) }
        }
        if let defaultModel, !defaultModel.isEmpty { self.defaultModel = defaultModel }
        if let defaultProvider, let value = ProviderID(rawValue: defaultProvider) { self.defaultProvider = value }
        if let effort, let value = Effort(rawValue: effort) { self.effort = value }
    }

    // MARK: Modelli

    /// Scarica l'elenco dei modelli da tutti i provider configurati, in parallelo.
    func refreshModels() async {
        let configured = apiKeys
        guard !configured.isEmpty else { return }
        isLoadingModels = true
        modelsError = nil
        defer { isLoadingModels = false }

        var fetched: [ProviderID: [ModelInfo]] = [:]
        var failures: [String] = []
        await withTaskGroup(of: (ProviderID, Result<[ModelInfo], Error>).self) { group in
            for (provider, key) in configured {
                group.addTask {
                    do {
                        let list = provider == .anthropic
                            ? try await AnthropicClient(apiKey: key).listModels()
                            : try await OpenAICompatibleClient(provider: provider, apiKey: key).listModels()
                        return (provider, .success(list))
                    } catch {
                        return (provider, .failure(error))
                    }
                }
            }
            for await (provider, result) in group {
                switch result {
                case .success(let list): fetched[provider] = list
                case .failure(let error): failures.append("\(provider.name): \(error.localizedDescription)")
                }
            }
        }

        // Mantiene i modelli già noti per i provider che non hanno risposto.
        var merged: [ModelInfo] = []
        for provider in ProviderID.allCases where configured[provider] != nil {
            merged += fetched[provider] ?? models.filter { $0.provider == provider }
        }
        models = merged
        saveModels()
        modelsError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    func models(for provider: ProviderID) -> [ModelInfo] {
        models.filter { $0.provider == provider }
    }

    private func saveModels() {
        defaults.set(try? JSONEncoder().encode(models), forKey: "models")
    }

    func displayName(for modelID: String) -> String {
        if let name = models.first(where: { $0.id == modelID })?.displayName {
            return name.replacingOccurrences(of: "Claude ", with: "")
        }
        guard modelID.hasPrefix("claude-") else { return modelID }
        // Senza elenco dei modelli: "claude-sonnet-5-5" diventa "Sonnet 5.5".
        let parts = modelID.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        guard let family = parts.first else { return modelID }
        let version = parts.dropFirst().filter { $0.allSatisfy(\.isNumber) && $0.count <= 2 }
        return ([family.capitalized] + (version.isEmpty ? [] : [version.joined(separator: ".")])).joined(separator: " ")
    }

    /// L'effort si invia solo ai modelli Anthropic che lo supportano.
    func effortParameter(for modelID: String) -> Effort? {
        models.first { $0.provider == .anthropic && $0.id == modelID }?.supportsEffort == true ? effort : nil
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

    func send(_ text: String, attachments: [Attachment] = [], to id: UUID) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty,
              !sending.contains(id), var conversation = store.conversation(id) else { return }
        conversation.messages.append(ChatMessage(
            role: .user, text: trimmed, attachments: attachments.isEmpty ? nil : attachments
        ))
        if conversation.title == Conversation.untitled {
            conversation.title = trimmed.isEmpty ? "Immagine" : String(trimmed.prefix(60))
        }
        conversation.updatedAt = Date()
        store.upsert(conversation)
        await generateReply(for: id)
    }

    /// Scarta l'ultima risposta e ne chiede una nuova.
    func regenerate(_ id: UUID) async {
        guard !sending.contains(id), var conversation = store.conversation(id) else { return }
        while conversation.messages.last?.role == .assistant { conversation.messages.removeLast() }
        conversation.updatedAt = Date()
        store.upsert(conversation)
        await generateReply(for: id)
    }

    /// Chiede una risposta per l'ultimo messaggio dell'utente (usato anche per "Riprova").
    func generateReply(for id: UUID) async {
        guard let conversation = store.conversation(id), !sending.contains(id) else { return }
        let provider = conversation.providerID
        guard let apiKey = settings.apiKey(for: provider), !apiKey.isEmpty else {
            errors[id] = "Manca la chiave API di \(provider.name). Aggiungila nelle impostazioni dell'iPhone."
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
            if provider != .anthropic {
                result = try await OpenAICompatibleClient(provider: provider, apiKey: apiKey).streamChat(
                    model: conversation.model,
                    messages: PayloadBuilder.openAIMessages(for: conversation),
                    onText: onText
                )
            } else {
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
                costUSD: provider == .anthropic ? Pricing.cost(model: servedModel, usage: result.usage) : nil
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
