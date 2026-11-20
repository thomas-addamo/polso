import Foundation

/// Servizi AI supportati. Anthropic usa l'API Messages; gli altri l'API compatibile con OpenAI.
enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic, groq, openai, openrouter, mistral

    var id: String { rawValue }

    var name: String {
        switch self {
        case .anthropic: "Anthropic"
        case .groq: "Groq"
        case .openai: "OpenAI"
        case .openrouter: "OpenRouter"
        case .mistral: "Mistral"
        }
    }

    var subtitle: String {
        switch self {
        case .anthropic: "Modelli Claude"
        case .groq: "Llama, Qwen, GPT-OSS e altri, molto veloci"
        case .openai: "Modelli GPT"
        case .openrouter: "Centinaia di modelli con una sola chiave"
        case .mistral: "Modelli Mistral"
        }
    }

    var icon: String {
        switch self {
        case .anthropic: "sparkle"
        case .groq: "bolt.fill"
        case .openai: "circle.hexagongrid.fill"
        case .openrouter: "arrow.triangle.branch"
        case .mistral: "wind"
        }
    }

    var baseURL: URL {
        switch self {
        case .anthropic: URL(string: "https://api.anthropic.com/v1")!
        case .groq: URL(string: "https://api.groq.com/openai/v1")!
        case .openai: URL(string: "https://api.openai.com/v1")!
        case .openrouter: URL(string: "https://openrouter.ai/api/v1")!
        case .mistral: URL(string: "https://api.mistral.ai/v1")!
        }
    }

    /// Pagina dove creare la chiave API.
    var keysURL: URL {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")!
        case .groq: URL(string: "https://console.groq.com/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .openrouter: URL(string: "https://openrouter.ai/keys")!
        case .mistral: URL(string: "https://console.mistral.ai/api-keys")!
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .groq: "gsk_…"
        case .openai: "sk-…"
        case .openrouter: "sk-or-…"
        case .mistral: "Chiave Mistral"
        }
    }

    /// L'account Anthropic mantiene il nome usato dalle versioni precedenti, così la chiave salvata resta valida.
    var keychainAccount: String {
        self == .anthropic ? "anthropic-api-key" : "\(rawValue)-api-key"
    }
}

extension Conversation {
    var providerID: ProviderID { provider ?? .anthropic }
}

extension ModelInfo {
    /// Identificativo univoco anche tra provider diversi.
    var key: String { "\(provider.rawValue)|\(id)" }
}
