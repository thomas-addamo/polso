import SwiftUI
import WidgetKit

/// Complicazione per il quadrante: apre Polso con un tocco.
struct ComplicationEntry: TimelineEntry {
    let date: Date
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { ComplicationEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        completion(Timeline(entries: [ComplicationEntry(date: .now)], policy: .never))
    }
}

private let accent = Color(red: 0.80, green: 0.40, blue: 0.25)
private let accentLight = Color(red: 0.93, green: 0.56, blue: 0.41)
private let gradient = LinearGradient(colors: [accentLight, accent], startPoint: .topLeading, endPoint: .bottomTrailing)

struct PolsoComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                Circle().fill(gradient)
                Image(systemName: "sparkle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .widgetAccentable()

        case .accessoryCorner:
            Image(systemName: "sparkle")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(accentLight)
                .widgetAccentable()
                .widgetLabel { Text("Polso") }

        case .accessoryInline:
            Label("Chiedi a Claude", systemImage: "sparkle")

        default:
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(gradient)
                    Image(systemName: "sparkle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Polso").font(.headline)
                    Text("Tocca per chiedere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

@main
struct PolsoComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PolsoComplication", provider: ComplicationProvider()) { entry in
            PolsoComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Polso")
        .description("Apri Polso dal quadrante.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}
