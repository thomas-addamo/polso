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

/// Riconosce a quale assistente ci si rivolge, partendo dal modello della chat.
enum AssistantName {
    /// Prefissi riconosciuti nell'ID del modello (anche nella forma "azienda/modello" di OpenRouter).
    private static let families: [(prefix: String, name: String)] = [
        ("claude", "Claude"), ("gpt-oss", "GPT-OSS"), ("gpt", "GPT"), ("chatgpt", "ChatGPT"),
        ("o1", "GPT"), ("o3", "GPT"), ("o4", "GPT"), ("llama", "Llama"), ("meta-llama", "Llama"),
        ("qwen", "Qwen"), ("qwq", "Qwen"), ("gemma", "Gemma"), ("gemini", "Gemini"),
        ("deepseek", "DeepSeek"), ("kimi", "Kimi"), ("moonshot", "Kimi"), ("mixtral", "Mixtral"),
        ("codestral", "Codestral"), ("magistral", "Magistral"), ("pixtral", "Pixtral"),
        ("devstral", "Devstral"), ("ministral", "Mistral"), ("mistral", "Mistral"),
        ("open-mistral", "Mistral"), ("grok", "Grok"), ("compound", "Compound"), ("allam", "ALLaM"),
        ("command", "Command"), ("phi", "Phi"), ("nemotron", "Nemotron"), ("glm", "GLM"),
    ]

    static func name(model: String, provider: ProviderID) -> String {
        if provider == .anthropic { return "Claude" }
        let id = model.lowercased()
        let last = id.split(separator: "/").last.map(String.init) ?? id
        for candidate in [last, id] {
            for family in families where candidate.hasPrefix(family.prefix) {
                return family.name
            }
        }
        for family in families where id.contains(family.prefix) && family.prefix.count > 3 {
            return family.name
        }
        return provider.name
    }
}

extension Conversation {
    /// Nome dell'assistente di questa chat (es. "Claude", "Llama", "GPT").
    var assistantName: String { AssistantName.name(model: model, provider: providerID) }
    /// Simbolo dell'avatar: la scintilla per Claude, l'icona del provider per gli altri.
    var assistantSymbol: String { providerID == .anthropic ? "sparkle" : providerID.icon }
}
