import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Archivio delle immagini allegate: un file JPEG per allegato.
/// `version` cambia a ogni nuova immagine, così le viste si aggiornano quando ne arriva una dall'altro dispositivo.
@Observable @MainActor
final class ImageStore {
    static let shared = ImageStore()
    private(set) var version = 0

    nonisolated static let directory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated static func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".jpg")
    }

    nonisolated static func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    nonisolated static func data(for id: UUID) -> Data? {
        try? Data(contentsOf: url(for: id))
    }

    #if canImport(UIKit)
    nonisolated static func image(for id: UUID) -> UIImage? {
        data(for: id).flatMap(UIImage.init(data:))
    }
    #endif

    /// Salva un'immagine nuova e restituisce l'allegato corrispondente.
    func save(_ data: Data) -> Attachment {
        let attachment = Attachment()
        try? data.write(to: Self.url(for: attachment.id), options: .atomic)
        version += 1
        return attachment
    }

    /// Salva un'immagine ricevuta dall'altro dispositivo.
    func store(_ data: Data, id: UUID) {
        guard !Self.exists(id) else { return }
        try? data.write(to: Self.url(for: id), options: .atomic)
        version += 1
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: Self.url(for: id))
    }
}
