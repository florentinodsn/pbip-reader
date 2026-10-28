import Foundation

/// Diagnostics complets d'un projet : ceux de la lecture, plus les contrôles de cohérence.
public enum Validator {
    /// `unusedMeasures` à faux : pas de `model.unusedMeasure` (modèle partagé avec des rapports
    /// publiés ailleurs, que l'outil ne voit pas).
    public static func validate(_ project: Project, unusedMeasures: Bool = true) -> [Diagnostic] {
        validate(project, lineage: LineageBuilder.build(project), unusedMeasures: unusedMeasures)
    }

    public static func validate(_ project: Project, lineage: Lineage, unusedMeasures: Bool = true) -> [Diagnostic] {
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

            // Mesures inutilisées : seulement si le rapport et le modèle sont lus ensemble, et sur
            // l'ensemble des rapports locaux qui pointent vers ce modèle.
            if unusedMeasures, project.semanticModel != nil {
                out += unusedMeasureDiagnostics(project, lineage: lineage, file: modelFile)
            }
        }
        return out.sortedForOutput()
    }

    static func unusedMeasureDiagnostics(_ project: Project, lineage: Lineage, file: String?) -> [Diagnostic] {
        var unused = lineage.unusedMeasures
        for sibling in project.siblingReports {
            var other = project
            other.report = sibling.report
            other.siblingReports = []
            let unusedThere = Set(LineageBuilder.build(other).unusedMeasures.map { Lineage.key($0.table, $0.name) })
            unused = unused.filter { unusedThere.contains(Lineage.key($0.table, $0.name)) }
        }
        let scope: String
        if project.siblingReports.isEmpty {
            scope = "is not used by this report"
        } else {
            let others = project.siblingReports.map(\.name).joined(separator: ", ")
            scope = "is used neither by this report nor by the other local reports on this model (\(others))"
        }
        return unused.map { entry in
            Diagnostic(.info, code: "model.unusedMeasure",
                       message: "Measure \(entry.displayName) \(scope): no visual or filter reaches it, directly or through other measures or functions.",
                       file: file)
        }
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
