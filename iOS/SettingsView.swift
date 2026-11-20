import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    ForEach(ProviderID.allCases) { provider in
                        NavigationLink {
                            ProviderKeyView(provider: provider)
                        } label: {
                            ProviderRow(provider: provider, connected: settings.apiKey(for: provider) != nil)
                        }
                    }
                } header: {
                    Text("Provider")
                } footer: {
                    Text("Collega uno o più servizi con la tua chiave API. Le chiavi restano nel Portachiavi e vengono inviate solo al tuo Apple Watch.")
                }

                Section {
                    Picker("Modello per le nuove chat", selection: Binding(
                        get: { "\(settings.defaultProvider.rawValue)|\(settings.defaultModel)" },
                        set: { key in
                            guard let model = settings.models.first(where: { $0.key == key }) else { return }
                            settings.defaultProvider = model.provider
                            settings.defaultModel = model.id
                        }
                    )) {
                        if !settings.models.contains(where: { $0.key == "\(settings.defaultProvider.rawValue)|\(settings.defaultModel)" }) {
                            Text(settings.displayName(for: settings.defaultModel))
                                .tag("\(settings.defaultProvider.rawValue)|\(settings.defaultModel)")
                        }
                        ForEach(settings.configuredProviders) { provider in
                            Section(provider.name) {
                                ForEach(settings.models(for: provider), id: \.key) { model in
                                    Text(settings.displayName(for: model.id)).tag(model.key)
                                }
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker("Effort (solo Claude)", selection: $settings.effort) {
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
                        Text("\(settings.models.count) modelli disponibili dai provider collegati. Il costo stimato e la spesa del mese valgono solo per i modelli Claude.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
        }
    }
}

private struct ProviderRow: View {
    let provider: ProviderID
    let connected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: provider.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    connected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.gray.opacity(0.5)),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name)
                Text(provider.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if connected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Collegato")
            }
        }
    }
}

struct ProviderKeyView: View {
    let provider: ProviderID

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    private var connected: Bool { settings.apiKey(for: provider) != nil }

    var body: some View {
        Form {
            Section {
                SecureField(provider.keyPlaceholder, text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(connected ? "Sostituisci chiave" : "Salva chiave") {
                    settings.setAPIKey(draft, for: provider)
                    draft = ""
                    Task { await settings.refreshModels() }
                    dismiss()
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                if connected {
                    Button("Rimuovi chiave", role: .destructive) {
                        settings.setAPIKey(nil, for: provider)
                    }
                }
            } header: {
                Text("Chiave API")
            } footer: {
                Text(connected ? "Chiave salvata nel Portachiavi." : "Nessuna chiave salvata.")
            }

            Section {
                Link(destination: provider.keysURL) {
                    Label("Crea una chiave su \(provider.name)", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("L'uso dell'API è a pagamento secondo il listino di \(provider.name), salvo eventuali piani gratuiti del servizio.")
            }

            if connected {
                Section("Modelli disponibili") {
                    let models = settings.models(for: provider)
                    if models.isEmpty {
                        Text("Nessun modello caricato.").foregroundStyle(.secondary)
                    }
                    ForEach(models, id: \.key) { model in
                        Text(settings.displayName(for: model.id))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(provider.name)
    }
}
