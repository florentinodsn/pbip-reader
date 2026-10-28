import Foundation

/// Lecteur TMDL (étape 4).
struct TMDLModelReader {
    let reader: FileReader
    let sink: DiagnosticSink

    func read(_ folder: URL) -> SemanticModel? {
        SemanticModel(format: .tmdl)
    }
}
