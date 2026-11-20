import Foundation

struct AnthropicAPIError: LocalizedError, Sendable {
    var status: Int
    var type: String?
    var message: String

    var errorDescription: String? {
        switch status {
        case 401: "Chiave API non valida. Controllala nelle impostazioni dell'iPhone."
        case 403: "La chiave API non ha i permessi per questa richiesta."
        case 404: "Modello non trovato: \(message)"
        case 429: "Limite di utilizzo raggiunto. Riprova tra poco."
        case 529: "I server sono sovraccarichi. Riprova tra poco."
        default: message
        }
    }
}

struct StreamResult: Sendable {
    var content: [JSONValue]
    var text: String
    var stopReason: String?
    var model: String?
    var usage: TokenUsage
}

/// Client HTTP minimale per l'API Messages di Anthropic.
/// Swift non ha un SDK ufficiale, quindi si usa HTTP diretto.
struct AnthropicClient: Sendable {
    static let baseURL = URL(string: "https://api.anthropic.com/v1")!
    static let apiVersion = "2026-10-21"
    /// Modelli che supportano il fallback lato server in caso di rifiuto.
    static let fallbackModels: Set<String> = [
        "claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    let apiKey: String
    var session: URLSession = .shared

    private func makeRequest(_ url: URL, method: String = "GET", body: Data? = nil, betas: [String] = []) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 600
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if !betas.isEmpty {
            req.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        req.httpBody = body
        return req
    }

    static func apiError(status: Int, data: Data) -> AnthropicAPIError {
        let json = try? JSONValue.parse(data)
        let message = json?["error"]?["message"]?.string
            ?? String(data: data, encoding: .utf8)
            ?? "Errore HTTP \(status)"
        return AnthropicAPIError(status: status, type: json?["error"]?["type"]?.string, message: message)
    }

    // MARK: - Models API

    /// Elenco dei modelli disponibili per questa chiave API (GET /v1/models, con paginazione).
    func listModels() async throws -> [ModelInfo] {
        var result: [ModelInfo] = []
        var afterID: String?
        repeat {
            var comps = URLComponents(url: Self.baseURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "limit", value: "100")]
            if let afterID { comps.queryItems?.append(URLQueryItem(name: "after_id", value: afterID)) }

            let (data, response) = try await session.data(for: makeRequest(comps.url!))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw Self.apiError(status: status, data: data) }

            let json = try JSONValue.parse(data)
            for item in json["data"]?.array ?? [] {
                guard let id = item["id"]?.string else { continue }
                result.append(ModelInfo(
                    id: id,
                    displayName: item["display_name"]?.string ?? id,
                    supportsEffort: item["capabilities"]?["effort"]?["supported"]?.bool ?? false
                ))
            }
            afterID = json["has_more"]?.bool == true ? json["last_id"]?.string : nil
        } while afterID != nil
        return result
    }

    // MARK: - Messages API (streaming)

    func streamMessage(
        model: String,
        messages: [JSONValue],
        effort: Effort?,
        onText: @escaping @MainActor (String) -> Void
    ) async throws -> StreamResult {
        var body: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .number(Double(AppConstants.maxTokens)),
            "stream": true,
            "system": .string(AppConstants.systemPrompt),
            "messages": .array(messages),
        ]
        if let effort {
            body["output_config"] = ["effort": .string(effort.rawValue)]
        }
        var betas: [String] = []
        if Self.fallbackModels.contains(model) {
            // In caso di rifiuto, l'API riprova automaticamente su un modello adatto.
            body["fallbacks"] = "default"
            betas.append("server-side-fallback-2026-07-01")
        }

        let request = makeRequest(
            Self.baseURL.appendingPathComponent("messages"),
            method: "POST",
            body: try JSONEncoder().encode(JSONValue.object(body)),
            betas: betas
        )

        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.apiError(status: status, data: data)
        }

        var blocks: [Int: [String: JSONValue]] = [:]
        var partialJSON: [Int: String] = [:]
        var stopReason: String?
        var servedModel: String?
        var fullText = ""
        var usage = TokenUsage()

        /// Aggiorna i contatori con i campi presenti (i valori dell'API sono cumulativi).
        func readUsage(_ json: JSONValue?) {
            guard let json else { return }
            if let v = json["input_tokens"]?.int { usage.inputTokens = v }
            if let v = json["output_tokens"]?.int { usage.outputTokens = v }
            if let v = json["cache_read_input_tokens"]?.int { usage.cacheReadTokens = v }
            if let v = json["cache_creation_input_tokens"]?.int { usage.cacheWriteTokens = v }
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let event = try? JSONValue.parse(Data(payload.utf8)) else { continue }

            switch event["type"]?.string {
            case "message_start":
                servedModel = event["message"]?["model"]?.string
                readUsage(event["message"]?["usage"])

            case "content_block_start":
                if let i = event["index"]?.int, let block = event["content_block"]?.object {
                    blocks[i] = block
                }

            case "content_block_delta":
                guard let i = event["index"]?.int, let delta = event["delta"], var block = blocks[i] else { continue }
                switch delta["type"]?.string {
                case "text_delta":
                    let t = delta["text"]?.string ?? ""
                    block["text"] = .string((block["text"]?.string ?? "") + t)
                    fullText += t
                    await onText(t)
                case "thinking_delta":
                    block["thinking"] = .string((block["thinking"]?.string ?? "") + (delta["thinking"]?.string ?? ""))
                case "signature_delta":
                    block["signature"] = delta["signature"]
                case "citations_delta":
                    if let citation = delta["citation"] {
                        block["citations"] = .array((block["citations"]?.array ?? []) + [citation])
                    }
                case "input_json_delta":
                    partialJSON[i, default: ""] += delta["partial_json"]?.string ?? ""
                default:
                    break
                }
                blocks[i] = block

            case "content_block_stop":
                if let i = event["index"]?.int, let partial = partialJSON[i], var block = blocks[i] {
                    block["input"] = (try? JSONValue.parse(Data(partial.utf8))) ?? [:]
                    blocks[i] = block
                }

            case "message_delta":
                if let reason = event["delta"]?["stop_reason"]?.string { stopReason = reason }
                readUsage(event["usage"])

            case "error":
                throw AnthropicAPIError(
                    status: 0,
                    type: event["error"]?["type"]?.string,
                    message: event["error"]?["message"]?.string ?? "Errore durante lo streaming"
                )

            default:
                break
            }
        }

        let content = blocks.keys.sorted().compactMap { blocks[$0].map(JSONValue.object) }
        return StreamResult(content: content, text: fullText, stopReason: stopReason, model: servedModel, usage: usage)
    }
}

/// Costruisce l'array `messages` della richiesta a partire da una conversazione salvata.
enum PayloadBuilder {
    private static let thinkingTypes: Set<String> = ["thinking", "redacted_thinking"]

    static func messages(for conversation: Conversation, stripThinking: Bool) -> [JSONValue] {
        conversation.messages.compactMap { message -> JSONValue? in
            switch message.role {
            case .user:
                return ["role": "user", "content": [["type": "text", "text": .string(message.text)]]]
            case .assistant:
                if message.isRefusal { return nil }
                var blocks = message.rawContent ?? [["type": "text", "text": .string(message.text)]]
                blocks = sanitize(blocks, stripThinking: stripThinking)
                guard !blocks.isEmpty else { return nil }
                return ["role": "assistant", "content": .array(blocks)]
            }
        }
    }

    static func hasThinking(_ conversation: Conversation) -> Bool {
        conversation.messages.contains { msg in
            msg.rawContent?.contains { thinkingTypes.contains($0["type"]?.string ?? "") } ?? false
        }
    }

    private static func sanitize(_ blocks: [JSONValue], stripThinking: Bool) -> [JSONValue] {
        var result = blocks
        // Dopo un fallback a metà risposta, i blocchi di ragionamento prima del
        // blocco `fallback` non vanno rimandati (il blocco `fallback` resta al suo posto).
        if let boundary = result.lastIndex(where: { $0["type"]?.string == "fallback" }) {
            result = result.enumerated().filter { index, block in
                let type = block["type"]?.string ?? ""
                return index >= boundary || !(thinkingTypes.contains(type) || type == "tool_use")
            }.map(\.element)
        }
        if stripThinking {
            result.removeAll { thinkingTypes.contains($0["type"]?.string ?? "") }
        }
        return result
    }
}
