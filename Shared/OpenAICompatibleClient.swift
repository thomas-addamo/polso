import Foundation

/// Client per i servizi con API compatibile con OpenAI (Groq, OpenAI, OpenRouter, Mistral).
struct OpenAICompatibleClient: Sendable {
    let provider: ProviderID
    let apiKey: String
    var session: URLSession = .shared

    /// Modelli che non servono per la chat (audio, immagini, moderazione…).
    private static let excludedFragments = [
        "whisper", "tts", "guard", "embed", "moderation", "dall-e", "audio",
        "realtime", "transcribe", "image", "search", "computer-use", "orpheus", "safeguard",
    ]

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: provider.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 600
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .openrouter {
            request.setValue("Polso", forHTTPHeaderField: "X-Title")
        }
        request.httpBody = body
        return request
    }

    private static func apiError(status: Int, data: Data) -> AnthropicAPIError {
        let json = try? JSONValue.parse(data)
        let message = json?["error"]?["message"]?.string
            ?? json?["message"]?.string
            ?? String(data: data, encoding: .utf8)
            ?? "Errore HTTP \(status)"
        return AnthropicAPIError(status: status, type: json?["error"]?["type"]?.string, message: message)
    }

    func listModels() async throws -> [ModelInfo] {
        let (data, response) = try await session.data(for: makeRequest("models"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.apiError(status: status, data: data) }

        let json = try JSONValue.parse(data)
        return (json["data"]?.array ?? []).compactMap { item -> ModelInfo? in
            guard let id = item["id"]?.string else { return nil }
            let lower = id.lowercased()
            guard !Self.excludedFragments.contains(where: lower.contains) else { return nil }
            return ModelInfo(id: id, displayName: item["name"]?.string ?? id, supportsEffort: false, provider: provider)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func streamChat(
        model: String,
        messages: [JSONValue],
        onText: @escaping @MainActor (String) -> Void
    ) async throws -> StreamResult {
        var body: [String: JSONValue] = [
            "model": .string(model),
            "stream": true,
            "messages": .array([["role": "system", "content": .string(AppConstants.systemPrompt)]] + messages),
        ]
        // OpenAI e Groq usano il nome nuovo del parametro; gli altri quello classico.
        let tokensKey = (provider == .openai || provider == .groq) ? "max_completion_tokens" : "max_tokens"
        body[tokensKey] = .number(Double(AppConstants.maxTokens))
        if provider != .mistral {
            body["stream_options"] = ["include_usage": true]
        }

        let request = makeRequest("chat/completions", method: "POST", body: try JSONEncoder().encode(JSONValue.object(body)))
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.apiError(status: status, data: data)
        }

        var text = ""
        var finishReason: String?
        var servedModel: String?
        var usage = TokenUsage()

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let chunk = try? JSONValue.parse(Data(payload.utf8)) else { continue }

            if let message = chunk["error"]?["message"]?.string {
                throw AnthropicAPIError(status: 0, type: nil, message: message)
            }
            if let model = chunk["model"]?.string { servedModel = model }
            if let choice = chunk["choices"]?.array?.first {
                if let delta = choice["delta"]?["content"]?.string, !delta.isEmpty {
                    text += delta
                    await onText(delta)
                }
                if let reason = choice["finish_reason"]?.string { finishReason = reason }
            }
            // Groq mette l'utilizzo anche in `x_groq.usage`.
            for candidate in [chunk["usage"], chunk["x_groq"]?["usage"]] {
                if let input = candidate?["prompt_tokens"]?.int { usage.inputTokens = input }
                if let output = candidate?["completion_tokens"]?.int { usage.outputTokens = output }
            }
        }

        return StreamResult(
            content: [],
            text: text,
            stopReason: finishReason == "length" ? "max_tokens" : finishReason,
            model: servedModel ?? model,
            usage: usage
        )
    }
}

extension PayloadBuilder {
    /// Cronologia nel formato OpenAI: solo testo e immagini, senza i blocchi specifici di Anthropic.
    static func openAIMessages(for conversation: Conversation) -> [JSONValue] {
        conversation.messages.compactMap { message -> JSONValue? in
            switch message.role {
            case .assistant:
                guard !message.isRefusal, !message.text.isEmpty else { return nil }
                return ["role": "assistant", "content": .string(message.text)]
            case .user:
                let attachments = message.attachments ?? []
                guard !attachments.isEmpty else {
                    return ["role": "user", "content": .string(message.text)]
                }
                var parts: [JSONValue] = []
                if !message.text.isEmpty {
                    parts.append(["type": "text", "text": .string(message.text)])
                }
                for attachment in attachments {
                    guard let data = ImageStore.data(for: attachment.id) else { continue }
                    let url = "data:\(attachment.mediaType);base64,\(data.base64EncodedString())"
                    parts.append(["type": "image_url", "image_url": ["url": .string(url)]])
                }
                return ["role": "user", "content": .array(parts)]
            }
        }
    }
}
