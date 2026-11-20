# Polso

App per **Apple Watch** (con app compagna per iPhone) per chattare con Claude tramite l'API di Anthropic.

- **iPhone**: inserisci la chiave API, crea e gestisci le chat, scegli il modello predefinito e l'effort.
- **Apple Watch**: vedi le chat già esistenti e rispondi a Claude con dettatura, Scribble o tastiera; puoi cambiare il modello di ogni chat.
- **Modelli**: l'elenco arriva dalla Models API (`GET /v1/models`), quindi mostra i modelli disponibili per la tua chiave. Quello predefinito è `claude-sonnet-5-5`.
- **Costi sotto controllo**: sotto ogni risposta c'è il costo stimato; l'elenco delle chat mostra la spesa del mese (iPhone + Watch). Le risposte sono limitate a 4.096 token.

> **Nota:** l'API di Anthropic non dà accesso alle chat di claude.ai. Le "chat esistenti" sono quelle create in Polso, salvate sul dispositivo e sincronizzate tra iPhone e Watch.

## Requisiti

- Xcode 27, iOS 18+, watchOS 11+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Una chiave API da [console.anthropic.com](https://console.anthropic.com). L'uso dell'API è a pagamento.

## Avvio

```bash
xcodegen generate
open Polso.xcodeproj
```

Per eseguirla su un dispositivo reale, scegli il tuo *Team* in *Signing & Capabilities* per entrambi i target (`Polso` e `PolsoWatch`).

## Struttura

| Cartella | Contenuto |
|---|---|
| `Shared/` | Client HTTP per l'API (streaming SSE), modelli dati, archivio delle chat, impostazioni, sincronizzazione WatchConnectivity |
| `iOS/` | Interfaccia dell'iPhone: elenco delle chat, chat, impostazioni |
| `Watch/` | Interfaccia del Watch: elenco delle chat, chat, scelta del modello |
| `project.yml` | Definizione del progetto per XcodeGen |

## Come funziona

- **API**: chiamate HTTP dirette a `POST /v1/messages` con `stream: true` (non esiste un SDK Swift ufficiale). Le risposte vengono salvate con i blocchi di contenuto originali e rimandate invariate nei turni successivi, come richiedono i modelli recenti per i blocchi di ragionamento.
- **Rifiuti**: sui modelli che lo supportano è attivo il fallback lato server (`fallbacks: "default"`). Le risposte rifiutate vengono mostrate, ma non rimandate all'API.
- **Sincronizzazione**: ogni modifica viaggia con `transferUserInfo`. All'avvio i due dispositivi si scambiano lo stato completo. Se la stessa chat cambia su entrambi i dispositivi, vince la versione più recente.
- **Chiave API**: è salvata nel Portachiavi e passa dall'iPhone al Watch tramite l'application context di WatchConnectivity.
- **Il Watch chiama l'API direttamente** (Wi-Fi, rete cellulare o connessione tramite iPhone).

## Limiti noti

- Se lo schermo del Watch si spegne durante una risposta lunga, la richiesta può interrompersi. In quel caso usa "Riprova".
