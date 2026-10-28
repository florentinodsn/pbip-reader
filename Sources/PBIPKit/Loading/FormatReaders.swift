import Foundation

/// Choisit le lecteur de rapport selon le format présent (`report.json` ou `definition/`).
struct ReportReader {
    let reader: FileReader
    let sink: DiagnosticSink

    func read(_ folder: URL) -> Report? {
        let legacy = folder.appendingPathComponent("report.json")
        let definition = folder.appendingPathComponent("definition")
        let hasLegacy = FileReader.exists(legacy)
        let hasPBIR = FileReader.isDirectory(definition)

        switch (hasLegacy, hasPBIR) {
        case (true, true):
            // Les deux formats ne doivent pas coexister ; on lit PBIR pour afficher quelque chose.
            sink.error("report.conflictingFormats",
                       "Report folder contains both report.json (PBIR-Legacy) and definition/ (PBIR); reading definition/.",
                       url: folder)
            return PBIRReader(reader: reader, sink: sink).read(definition)
        case (false, true):
            return PBIRReader(reader: reader, sink: sink).read(definition)
        case (true, false):
            return LegacyReportReader(reader: reader, sink: sink).read(legacy)
        case (false, false):
            sink.error("report.noDefinition", "Report folder has neither report.json nor definition/.", url: folder)
            return nil
        }
    }
}

/// Choisit le lecteur de modèle selon le format présent (`model.bim` ou `definition/`).
struct SemanticModelReader {
    let reader: FileReader
    let sink: DiagnosticSink

    func read(_ folder: URL) -> SemanticModel? {
        let pbism = folder.appendingPathComponent("definition.pbism")
        // Les premiers projets (dossiers `.Dataset`) nommaient ce fichier `definition.pbidataset`.
        let pbidataset = folder.appendingPathComponent("definition.pbidataset")
        if FileReader.exists(pbism) {
            _ = reader.readJSON(pbism)
        } else if FileReader.exists(pbidataset) {
            _ = reader.readJSON(pbidataset)
            sink.info("pbism.legacyName", "Semantic model uses the older definition.pbidataset file name.", url: pbidataset)
        } else {
            sink.error("pbism.missing", "Semantic model folder has no definition.pbism.", url: folder)
        }

        let bim = folder.appendingPathComponent("model.bim")
        let definition = folder.appendingPathComponent("definition")
        let hasBim = FileReader.exists(bim)
        let hasTMDL = FileReader.isDirectory(definition)

        switch (hasBim, hasTMDL) {
        case (true, true):
            sink.error("model.conflictingFormats",
                       "Semantic model folder contains both model.bim (TMSL) and definition/ (TMDL); reading definition/.",
                       url: folder)
            return TMDLModelReader(reader: reader, sink: sink).read(definition)
        case (false, true):
            return TMDLModelReader(reader: reader, sink: sink).read(definition)
        case (true, false):
            return BIMReader(reader: reader, sink: sink).read(bim)
        case (false, false):
            sink.error("model.noDefinition", "Semantic model folder has neither model.bim nor definition/.", url: folder)
            return nil
        }
    }
}
