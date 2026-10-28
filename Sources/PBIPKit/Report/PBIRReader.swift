import Foundation

/// Lecteur PBIR (étape 6).
struct PBIRReader {
    let reader: FileReader
    let sink: DiagnosticSink

    func read(_ folder: URL) -> Report? {
        Report(format: .pbir)
    }
}
