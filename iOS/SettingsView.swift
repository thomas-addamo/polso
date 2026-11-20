import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var keyDraft = ""

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Salva chiave") {
                        settings.setAPIKey(keyDraft)
                        keyDraft = ""
                        Task { await settings.refreshModels() }
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if settings.hasAPIKey {
                        Button("Rimuovi chiave", role: .destructive) { settings.setAPIKey(nil) }
                    }
                } header: {
                    Text("Chiave API Anthropic")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.hasAPIKey ? "Chiave salvata nel Portachiavi." : "Nessuna chiave salvata.")
                        Text("La chiave resta sul dispositivo e viene inviata solo all'Apple Watch abbinato. Puoi crearla su console.anthropic.com. L'uso dell'API è a pagamento.")
                    }
                }

                Section {
                    Picker("Modello per le nuove chat", selection: $settings.defaultModel) {
                        if !settings.models.contains(where: { $0.id == settings.defaultModel }) {
                            Text(settings.defaultModel).tag(settings.defaultModel)
                        }
                        ForEach(settings.models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    Picker("Effort", selection: $settings.effort) {
                        ForEach(Effort.allCases) { Text($0.label).tag($0) }
                    }
                    Button {
                        Task { await settings.refreshModels() }
                    } label: {
                        HStack {
                            Text("Aggiorna l'elenco dei modelli")
                            if settings.isLoadingModels { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(!settings.hasAPIKey || settings.isLoadingModels)
                } header: {
                    Text("Modelli")
                } footer: {
                    if let error = settings.modelsError {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("L'elenco arriva dall'API, con i modelli disponibili per la tua chiave. Un effort più basso dà risposte più rapide ed economiche.")
                    }
                }
            }
            .navigationTitle("Impostazioni")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
        }
    }
}
