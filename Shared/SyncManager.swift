import Foundation
import WatchConnectivity

/// Sincronizza conversazioni e impostazioni tra iPhone e Apple Watch.
///
/// - Le singole modifiche viaggiano con `transferUserInfo` (in coda, consegnate anche
///   se l'altro dispositivo non è raggiungibile in quel momento).
/// - All'avvio ogni lato chiede all'altro uno stato completo, inviato come file.
/// - La chiave API e le impostazioni vanno dall'iPhone al Watch con l'application context.
@MainActor
final class SyncManager: NSObject {
    static let shared = SyncManager()

    private weak var store: ConversationStore?
    private weak var settings: SettingsStore?
    private(set) var isActive = false

    private var session: WCSession? { WCSession.isSupported() ? .default : nil }

    func start(store: ConversationStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        store.onUpsert = { [weak self] in self?.sendUpsert($0) }
        store.onDelete = { [weak self] in self?.sendDelete($0) }
        #if os(iOS)
        settings.onChange = { [weak self] in self?.pushSettings() }
        #endif
        session?.delegate = self
        session?.activate()
    }

    private var canSend: Bool {
        guard let session, session.activationState == .activated else { return false }
        #if os(iOS)
        return session.isPaired && session.isWatchAppInstalled
        #else
        return true
        #endif
    }

    // MARK: Invio

    private func sendUpsert(_ conversation: Conversation) {
        guard canSend, let data = try? JSONEncoder().encode(conversation) else { return }
        session?.transferUserInfo(["kind": "upsert", "data": data])
        sendImages(in: [conversation], onlyNew: true)
    }

    /// Invia i file delle immagini allegate (una sola volta per immagine, salvo sincronizzazione completa).
    private func sendImages(in conversations: [Conversation], onlyNew: Bool) {
        guard canSend else { return }
        var sent = Set(UserDefaults.standard.stringArray(forKey: "sentImages") ?? [])
        for message in conversations.flatMap(\.messages) {
            for attachment in message.attachments ?? [] {
                let key = attachment.id.uuidString
                guard !(onlyNew && sent.contains(key)), ImageStore.exists(attachment.id) else { continue }
                session?.transferFile(ImageStore.url(for: attachment.id), metadata: ["kind": "image", "id": key])
                sent.insert(key)
            }
        }
        UserDefaults.standard.set(Array(sent), forKey: "sentImages")
    }

    private func sendDelete(_ id: UUID) {
        guard canSend else { return }
        session?.transferUserInfo(["kind": "delete", "id": id.uuidString])
    }

    private func requestFullSync() {
        guard canSend else { return }
        session?.transferUserInfo(["kind": "requestFull"])
    }

    private func sendFullSync() {
        guard canSend, let data = try? store?.exportState() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("polso-sync-\(UUID().uuidString).json")
        guard (try? data.write(to: url)) != nil else { return }
        session?.transferFile(url, metadata: ["kind": "full"])
        if let conversations = store?.conversations {
            sendImages(in: conversations, onlyNew: false)
        }
    }

    #if os(iOS)
    func pushSettings() {
        guard canSend, let settings else { return }
        var keys: [String: String] = [:]
        for (provider, key) in settings.apiKeys { keys[provider.rawValue] = key }
        try? session?.updateApplicationContext([
            "apiKeys": keys,
            "defaultModel": settings.defaultModel,
            "defaultProvider": settings.defaultProvider.rawValue,
            "effort": settings.effort.rawValue,
        ])
    }
    #endif

    // MARK: Ricezione

    fileprivate func didActivate() {
        isActive = true
        #if os(iOS)
        pushSettings()
        #else
        if let context = session?.receivedApplicationContext, !context.isEmpty {
            applySettings(context)
        }
        #endif
        requestFullSync()
    }

    fileprivate func handle(kind: String?, data: Data?, id: String?) {
        switch kind {
        case "upsert":
            if let data, let conversation = try? JSONDecoder().decode(Conversation.self, from: data) {
                store?.mergeRemote(conversation)
            }
        case "delete":
            if let id, let uuid = UUID(uuidString: id) { store?.applyRemoteDelete(uuid) }
        case "requestFull":
            sendFullSync()
        case "full":
            if let data { store?.importState(data) }
        case "image":
            if let data, let id, let uuid = UUID(uuidString: id) {
                ImageStore.shared.store(data, id: uuid)
            }
        default:
            break
        }
    }

    fileprivate func applySettings(_ context: [String: Any]) {
        var keys = context["apiKeys"] as? [String: String] ?? [:]
        // Formato delle versioni precedenti: solo la chiave Anthropic.
        if keys.isEmpty, let legacy = context["apiKey"] as? String, !legacy.isEmpty {
            keys[ProviderID.anthropic.rawValue] = legacy
        }
        settings?.applyRemote(
            keys: keys,
            defaultModel: context["defaultModel"] as? String,
            defaultProvider: context["defaultProvider"] as? String,
            effort: context["effort"] as? String
        )
        Task { await settings?.refreshModels() }
    }
}

extension SyncManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in self.didActivate() }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }
        Task { @MainActor in
            self.pushSettings()
            self.sendFullSync()
        }
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let kind = userInfo["kind"] as? String
        let data = userInfo["data"] as? Data
        let id = userInfo["id"] as? String
        Task { @MainActor in self.handle(kind: kind, data: data, id: id) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Il file viene eliminato al termine di questo metodo: va letto subito.
        let data = try? Data(contentsOf: file.fileURL)
        let kind = file.metadata?["kind"] as? String
        let id = file.metadata?["id"] as? String
        Task { @MainActor in self.handle(kind: kind, data: data, id: id) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        // Elimina solo i file temporanei della sincronizzazione completa, non le immagini.
        let url = fileTransfer.file.fileURL
        if url.lastPathComponent.hasPrefix("polso-sync-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let keys = applicationContext["apiKeys"] as? [String: String]
        let legacyKey = applicationContext["apiKey"] as? String
        let model = applicationContext["defaultModel"] as? String
        let provider = applicationContext["defaultProvider"] as? String
        let effort = applicationContext["effort"] as? String
        Task { @MainActor in
            self.applySettings([
                "apiKeys": keys as Any, "apiKey": legacyKey as Any, "defaultModel": model as Any,
                "defaultProvider": provider as Any, "effort": effort as Any,
            ])
        }
    }
}
