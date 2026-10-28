import Foundation

/// Lecteur model.bim (étape 5).
struct BIMReader {
    let reader: FileReader
    let sink: DiagnosticSink

    func read(_ url: URL) -> SemanticModel? {
        guard reader.readJSON(url) != nil else { return nil }
        return SemanticModel(format: .bim)
    }
}
