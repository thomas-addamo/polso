import Foundation

enum AppConstants {
    /// Modello predefinito per le nuove chat.
    static let defaultModel = "claude-opus-5-5"
    static let maxTokens = 16_000

    /// Il prompt di sistema deve restare identico su iPhone e Watch e nel tempo:
    /// cambiarlo a metà conversazione invaliderebbe i thinking block già salvati.
    static let systemPrompt = """
    Sei un assistente utile. L'utente legge le tue risposte su un Apple Watch o su un iPhone: \
    preferisci risposte brevi e chiare, con paragrafi corti. Evita tabelle e blocchi di codice \
    lunghi, a meno che non vengano chiesti esplicitamente. Rispondi nella lingua dell'utente.
    """
}

enum Role: String, Codable, Sendable {
    case user, assistant
}

struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var role: Role
    /// Testo da mostrare (concatenazione dei blocchi `text`).
    var text: String
    var createdAt = Date()
    /// Modello che ha prodotto la risposta (solo per i messaggi dell'assistente).
    var model: String? = nil
    /// Blocchi di contenuto originali dell'API, rimandati invariati nei turni successivi.
    var rawContent: [JSONValue]? = nil
    /// La risposta è stata rifiutata dai filtri di sicurezza: non viene rimandata all'API.
    var isRefusal = false
}

struct Conversation: Codable, Identifiable, Hashable, Sendable {
    static let untitled = "Nuova chat"

    var id = UUID()
    var title: String = Conversation.untitled
    var model: String
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []

    var preview: String { messages.last?.text ?? "Nessun messaggio" }
}

struct ModelInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var supportsEffort: Bool
}

enum Effort: String, CaseIterable, Codable, Identifiable, Sendable {
    case low, medium, high, xhigh, max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: "Bassa (più veloce)"
        case .medium: "Media"
        case .high: "Alta"
        case .xhigh: "Molto alta"
        case .max: "Massima"
        }
    }
}
