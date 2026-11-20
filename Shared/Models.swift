import Foundation

enum AppConstants {
    /// Modello predefinito per le nuove chat: Sonnet 5.5, buon equilibrio tra qualità e costo.
    static let defaultModel = "claude-sonnet-5-5"
    /// Tetto alla lunghezza di ogni risposta (include il ragionamento): tiene basso il costo massimo.
    static let maxTokens = 4_096

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
    /// Token usati per produrre la risposta, come riportati dall'API.
    var usage: TokenUsage? = nil
    /// Costo stimato in dollari della richiesta che ha prodotto la risposta.
    var costUSD: Double? = nil
    /// Immagini allegate dall'utente (file salvati in ImageStore).
    var attachments: [Attachment]? = nil

    var hasAttachments: Bool { !(attachments ?? []).isEmpty }
}

struct Attachment: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var mediaType = "image/jpeg"
}

struct TokenUsage: Codable, Hashable, Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0

    var totalInput: Int { inputTokens + cacheReadTokens + cacheWriteTokens }
}

struct SpendEntry: Codable, Hashable, Sendable {
    var date: Date
    var cost: Double
}

/// Listino Anthropic in dollari per milione di token (aggiornato a novembre 2026).
/// Serve solo per una stima: l'importo reale è nella Console di Anthropic.
enum Pricing {
    struct Rate { var input: Double; var output: Double; var cacheRead: Double }

    static let rates: [String: Rate] = [
        "claude-haiku-5-5": Rate(input: 0.10, output: 0.50, cacheRead: 0.01),
        "claude-sonnet-5-5": Rate(input: 2, output: 10, cacheRead: 0.10),
        "claude-opus-5-5": Rate(input: 4, output: 20, cacheRead: 0.20),
        "claude-fable-5-2": Rate(input: 8, output: 40, cacheRead: 0.20),
        "claude-fable-5-1": Rate(input: 10, output: 50, cacheRead: 0.25),
        "claude-fable-5": Rate(input: 10, output: 50, cacheRead: 1.00),
        "claude-opus-5": Rate(input: 5, output: 25, cacheRead: 0.50),
        "claude-sonnet-5": Rate(input: 2, output: 10, cacheRead: 0.20),
        "claude-opus-4-8": Rate(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-7": Rate(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-6": Rate(input: 5, output: 25, cacheRead: 0.50),
        "claude-sonnet-4-6": Rate(input: 3, output: 15, cacheRead: 0.30),
        "claude-haiku-4-5": Rate(input: 1, output: 5, cacheRead: 0.10),
    ]

    static func rate(for model: String) -> Rate? {
        if let exact = rates[model] { return exact }
        // ID con suffisso (es. data): prende la chiave più lunga che fa da prefisso.
        return rates.keys
            .filter { model.hasPrefix($0 + "-") }
            .max { $0.count < $1.count }
            .flatMap { rates[$0] }
    }

    static func cost(model: String, usage: TokenUsage) -> Double? {
        guard var rate = rate(for: model) else { return nil }
        // Haiku 5.5 ha un prezzo più alto oltre i 100K token di prompt.
        if model.hasPrefix("claude-haiku-5-5"), usage.totalInput > 100_000 {
            rate = Rate(input: 0.50, output: 2.50, cacheRead: 0.05)
        }
        let perToken = 1_000_000.0
        return (Double(usage.inputTokens) * rate.input
            + Double(usage.cacheWriteTokens) * rate.input * 1.25
            + Double(usage.cacheReadTokens) * rate.cacheRead
            + Double(usage.outputTokens) * rate.output) / perToken
    }

    static func format(_ usd: Double) -> String {
        if usd == 0 { return "$0" }
        if usd < 0.01 { return String(format: "$%.4f", usd) }
        return String(format: "$%.2f", usd)
    }
}

struct Conversation: Codable, Identifiable, Hashable, Sendable {
    static let untitled = "Nuova chat"

    var id = UUID()
    var title: String = Conversation.untitled
    var model: String
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []

    var preview: String {
        guard let last = messages.last else { return "Nessun messaggio" }
        if last.text.isEmpty && last.hasAttachments { return "Immagine" }
        return last.text
    }
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
