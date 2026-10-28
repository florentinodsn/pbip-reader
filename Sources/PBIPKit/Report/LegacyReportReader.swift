import Foundation

/// Lecteur PBIR-Legacy (étape 6).
struct LegacyReportReader {
    let reader: FileReader
    let sink: DiagnosticSink

    func read(_ url: URL) -> Report? {
        guard reader.readJSON(url) != nil else { return nil }
        return Report(format: .legacy)
    }
}
