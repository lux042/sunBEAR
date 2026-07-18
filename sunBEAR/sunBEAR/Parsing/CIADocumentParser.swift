import Foundation
import SwiftSoup

struct CIADocumentParser: Sendable {
    func parse(html: String, sourceURL: URL) -> CIADocumentRecord? {
        guard
            let document = try? SwiftSoup.parse(html, sourceURL.absoluteString),
            let titleElement = try? document.select("h1.documentFirstHeading").first(),
            let title = try? titleElement.text(),
            !title.isEmpty
        else {
            return nil
        }

        var rawMetadata: [String: String] = [:]
        var normalizedMetadata: [String: String] = [:]

        if let fields = try? document.select(".node-document .field") {
            for field in fields {
                guard
                    let labelElement = try? field.select(".field-label").first(),
                    let label = try? labelElement.text(),
                    !label.isEmpty,
                    let valueElement = try? field.select(".field-items .field-item").first(),
                    let value = try? valueElement.text()
                else {
                    continue
                }

                let originalLabel = cleanOriginalLabel(label)
                let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                rawMetadata[originalLabel] = cleanValue
                normalizedMetadata[normalizeLabel(originalLabel)] = cleanValue
            }
        }

        let pdfURL: URL? = {
            guard
                let href = try? document
                    .select("a[type^=application/pdf], a[href$=.pdf]")
                    .first()?
                    .attr("abs:href"),
                !href.isEmpty
            else {
                return nil
            }

            return URL(string: href)
        }()

        return CIADocumentRecord(
            sourceURL: sourceURL,
            title: title,
            documentType: normalizedMetadata["document type"],
            collection: normalizedMetadata["collection"],
            documentNumber: normalizedMetadata["document number (foia) /esdn (crest)"],
            releaseDecision: normalizedMetadata["release decision"],
            originalClassification: normalizedMetadata["original classification"],
            documentPageCount: normalizedMetadata["document page count"].flatMap(Int.init),
            documentCreationDate: dateValue(
                in: document,
                selector: ".field-name-field-creation-date"
            ),
            documentReleaseDate: dateValue(
                in: document,
                selector: ".field-name-field-release-date"
            ),
            sequenceNumber: normalizedMetadata["sequence number"],
            publicationDate: dateValue(
                in: document,
                selector: ".field-name-field-pub-date"
            ),
            contentType: normalizedMetadata["content type"],
            caseNumber: nonempty(normalizedMetadata["case number"]),
            body: nonempty(normalizedMetadata["body"]),
            pdfURL: pdfURL,
            rawMetadata: rawMetadata
        )
    }

    private func cleanOriginalLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    }

    private func normalizeLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            .lowercased()
    }

    private func dateValue(in document: Document, selector: String) -> String? {
        guard
            let value = try? document
                .select("\(selector) [content]")
                .first()?
                .attr("content"),
            value.count >= 10
        else {
            return nil
        }

        return String(value.prefix(10))
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
