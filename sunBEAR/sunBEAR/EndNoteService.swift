import AppKit
import Foundation

enum EndNoteService {
    enum SendError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "EndNote could not be opened. Install EndNote and try again, or use Download EndNote File for manual import."
            }
        }
    }

    @MainActor
    static func send(items: [Item], sessionName: String) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sunBEAR-EndNote", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = safeFilename("CIA \(sessionName).enw")
        let fileURL = directory.appendingPathComponent(filename)
        try ExportService.endNoteImport(items: items).write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if let endNoteURL = endNoteApplicationURL() {
            try await NSWorkspace.shared.open([fileURL], withApplicationAt: endNoteURL, configuration: configuration)
            return
        }

        guard NSWorkspace.shared.open(fileURL) else { throw SendError.unavailable }
    }

    private static func endNoteApplicationURL() -> URL? {
        // Bundle identifiers used by recent and legacy macOS EndNote releases.
        for identifier in ["com.clarivate.EndNote", "com.ThomsonResearchSoft.EndNote"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) { return url }
        }
        return nil
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?\"<>|").union(.newlines)
        let cleaned = value.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "CIA sunBEAR export.enw" : String(cleaned.prefix(180))
    }
}
