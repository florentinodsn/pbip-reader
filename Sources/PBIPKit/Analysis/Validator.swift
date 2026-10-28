import Foundation

/// Diagnostics complets d'un projet : ceux de la lecture, plus les contrôles de cohérence.
public enum Validator {
    public static func validate(_ project: Project) -> [Diagnostic] {
        validate(project, lineage: LineageBuilder.build(project))
    }

    public static func validate(_ project: Project, lineage: Lineage) -> [Diagnostic] {
        var out = project.diagnostics
        let modelFile = project.semanticModelPath

        if let model = project.semanticModel {
            out += checkRelationships(model, file: modelFile)
            out += checkHierarchies(model, file: modelFile)
            out += checkDAX(model, file: modelFile)
        }

        if let report = project.report {
            for visual in lineage.visuals {
                let file = visualFile(project, report: report, pageId: visual.pageId, visualId: visual.visualId)
                let label = "Page '\(visual.page)', \(visual.visualType) \(visual.visualTitle.map { "\"\($0)\"" } ?? visual.visualId)"
                out += fieldDiagnostics(visual.fields, context: label, file: file)
            }
            out += fieldDiagnostics(lineage.filters, context: "Filter", file: project.reportPath)

            // Mesures inutilisées : seulement si le rapport et le modèle sont lus ensemble.
            if project.semanticModel != nil {
                for entry in lineage.unusedMeasures {
                    out.append(Diagnostic(.info, code: "model.unusedMeasure",
                                          message: "Measure \(entry.displayName) is not used by this report: no visual or filter reaches it, directly or through another measure.",
                                          file: modelFile))
                }
            }
        }
        return out.sortedForOutput()
    }

    static func fieldDiagnostics(_ fields: [Lineage.ResolvedField], context: String, file: String?) -> [Diagnostic] {
        fields.compactMap { resolved in
            let f = resolved.field
            let kind = f.kind == .hierarchyLevel ? "hierarchy level" : f.kind.rawValue
            switch resolved.status {
            case .ok, .notChecked:
                return nil
            case .unknownTable:
                return Diagnostic(.error, code: "report.unknownTable",
                                  message: "\(context): \(kind) \(f.displayName) refers to unknown table '\(f.table)'.", file: file)
            case .unknownField:
                return Diagnostic(.error, code: "report.unknownField",
                                  message: "\(context): \(kind) \(f.displayName) does not exist in the semantic model.", file: file)
            case .kindMismatch:
                return Diagnostic(.warning, code: "report.kindMismatch",
                                  message: "\(context): \(f.displayName) is used as a \(kind) but the model defines it as a \(f.kind == .measure ? "column" : "measure").",
                                  file: file)
            }
        }
    }

    static func checkRelationships(_ model: SemanticModel, file: String?) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for r in model.relationships {
            for end in [r.from, r.to] {
                guard let table = model.table(named: end.table) else {
                    out.append(Diagnostic(.error, code: "model.brokenRelationship",
                                          message: "Relationship \(r.id) (\(r.from.displayName) → \(r.to.displayName)) refers to unknown table '\(end.table)'.",
                                          file: file))
                    continue
                }
                if table.column(named: end.column) == nil {
                    out.append(Diagnostic(.error, code: "model.brokenRelationship",
                                          message: "Relationship \(r.id) (\(r.from.displayName) → \(r.to.displayName)) refers to unknown column \(end.displayName).",
                                          file: file))
                }
            }
        }
        return out
    }

    static func checkHierarchies(_ model: SemanticModel, file: String?) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for table in model.tables {
            for h in table.hierarchies {
                for level in h.levels where table.column(named: level.column) == nil {
                    out.append(Diagnostic(.error, code: "model.brokenHierarchy",
                                          message: "Hierarchy \(table.name)[\(h.name)], level '\(level.name)', refers to unknown column '\(level.column)'.",
                                          file: file))
                }
            }
        }
        return out
    }

    /// Références qualifiées vers une table connue mais un objet absent. Une table inconnue est
    /// ignorée : ce peut être une variable de table (`VAR t = … RETURN t[col]`).
    static func checkDAX(_ model: SemanticModel, file: String?) -> [Diagnostic] {
        var out: [Diagnostic] = []
        func check(_ owner: String, _ expression: String) {
            var seen = Set<DAXReference>()
            for ref in DAXScanner.references(in: expression) where seen.insert(ref).inserted {
                guard let tableName = ref.table, let table = model.table(named: tableName) else { continue }
                if table.column(named: ref.name) == nil, table.measure(named: ref.name) == nil {
                    out.append(Diagnostic(.warning, code: "dax.unknownReference",
                                          message: "\(owner) references \(table.name)[\(ref.name)], which does not exist.", file: file))
                }
            }
        }
        for table in model.tables {
            for m in table.measures { check("Measure \(table.name)[\(m.name)]", m.expression) }
            for c in table.columns { if let e = c.expression { check("Column \(table.name)[\(c.name)]", e) } }
        }
        return out
    }

    /// Fichier du visuel en PBIR (si le dossier porte son nom), sinon le fichier du rapport.
    static func visualFile(_ project: Project, report: Report, pageId: String, visualId: String) -> String? {
        guard let reportPath = project.reportPath else { return nil }
        guard report.format == .pbir else { return reportPath + "/report.json" }
        let path = "\(reportPath)/definition/pages/\(pageId)/visuals/\(visualId)/visual.json"
        return FileReader.exists(project.rootURL.appendingPathComponent(path)) ? path : reportPath
    }
}
