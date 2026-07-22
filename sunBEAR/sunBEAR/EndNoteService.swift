import AppKit
import Foundation

enum EndNoteService {
    enum SendError: LocalizedError {
        case unavailable
        case importFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "EndNote could not be opened. Install EndNote and try again, or use Download EndNote File for manual import."
            case .importFailed(let message):
                "EndNote import failed: \(message)"
            }
        }
    }

    @MainActor
    static func send(items: [Item], sessionName: String) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sunBEAR-EndNote", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = safeFilename("sunBEAR \(sessionName).xml")
        let fileURL = directory.appendingPathComponent(filename)
        try ExportService.endNoteXML(items: items).write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if let endNoteURL = endNoteApplicationURL() {
            _ = try await NSWorkspace.shared.openApplication(at: endNoteURL, configuration: configuration)
            try await importXML(fileURL, bundleIdentifier: Bundle(url: endNoteURL)?.bundleIdentifier ?? "com.ThomsonResearchSoft.EndNote")
            return
        }

        guard NSWorkspace.shared.open(fileURL) else { throw SendError.unavailable }
    }

    private static func importXML(_ fileURL: URL, bundleIdentifier: String) async throws {
        let path = appleScriptString(fileURL.path)
        let identifier = appleScriptString(bundleIdentifier)
        let script = """
        set xmlText to read POSIX file "\(path)" as «class utf8»
        tell application id "\(identifier)"
            if (count of documents) is 0 then error "Open an EndNote library, then try again."
            import {xmlText} into front document
            activate
        end tell
        """
        // NSWorkspace can report a successful launch slightly before EndNote's
        // Apple-event endpoint is ready. Retry only the transient -600 error;
        // surface real problems (such as no open library) immediately.
        for attempt in 0..<30 {
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: script) else {
                throw SendError.importFailed("The EndNote automation script could not be created.")
            }
            appleScript.executeAndReturnError(&error)
            guard let error else { return }

            let number = error[NSAppleScript.errorNumber] as? Int
            if number == -600, attempt < 29 {
                try await Task.sleep(for: .milliseconds(200))
                continue
            }
            let message = error[NSAppleScript.errorMessage] as? String ?? error.description
            throw SendError.importFailed(message)
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
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
        return cleaned.isEmpty ? "sunBEAR EndNote export.xml" : String(cleaned.prefix(180))
    }
}
