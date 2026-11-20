import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Palette calda, coordinata con l'icona dell'app.
enum Theme {
    static let accent = Color(red: 0.80, green: 0.40, blue: 0.25)
    static let accentLight = Color(red: 0.93, green: 0.56, blue: 0.41)
    static let gradient = LinearGradient(
        colors: [accentLight, accent], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    #if os(iOS)
    static let background = adaptive(
        light: UIColor(red: 0.985, green: 0.965, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.09, green: 0.08, blue: 0.075, alpha: 1)
    )
    static let surface = adaptive(
        light: .white,
        dark: UIColor(white: 1, alpha: 0.07)
    )
    static let codeBackground = adaptive(
        light: UIColor(red: 0.95, green: 0.925, blue: 0.895, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.055)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    #endif
}

/// Avatar dell'assistente: scintilla bianca su cerchio a gradiente.
struct AssistantAvatar: View {
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(Theme.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// Miniatura di un'immagine allegata (si aggiorna quando l'immagine arriva dall'altro dispositivo).
struct AttachmentImage: View {
    let attachment: Attachment
    var contentMode: ContentMode = .fill

    var body: some View {
        let _ = ImageStore.shared.version
        if let image = ImageStore.image(for: attachment.id) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}
