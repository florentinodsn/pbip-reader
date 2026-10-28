import Foundation

/// Rendu de `pbip info`.
public struct InfoRenderer {
    public var style: Style

    public init(style: Style) {
        self.style = style
    }

    public func render(_ project: Project, format: OutputFormat) -> String {
        let summary = ProjectSummary(project)
        switch format {
        case .json: return JSONOutput.encode(summary)
        case .text: return text(summary)
        case .markdown: return markdown(summary)
        }
    }

    func rows(_ s: ProjectSummary) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let path = s.reportPath {
            rows.append(("Report", "\(path) (\(s.reportFormat.map(Self.label) ?? "unreadable"))"))
        }
        if let ref = s.datasetReference {
            rows.append(("Model reference", Format.reference(ref)))
        }
        if let path = s.semanticModelPath {
            var details = [s.semanticModelFormat.map(Self.label) ?? "unreadable"]
            if let level = s.compatibilityLevel { details.append("compatibility level \(level)") }
            if let culture = s.culture { details.append("culture \(culture)") }
            rows.append(("Semantic model", "\(path) (\(details.joined(separator: ", ")))"))
        }
        let c = s.counts
        if s.reportFormat != nil {
            rows.append(("Report content", "\(Format.plural(c.pages, "page")), \(Format.plural(c.visuals, "visual")), \(Format.plural(c.bookmarks, "bookmark"))"))
        }
        if s.semanticModelFormat != nil {
            var content = [Format.plural(c.tables, "table"), Format.plural(c.columns, "column"), Format.plural(c.measures, "measure"),
                           Format.plural(c.relationships, "relationship"), Format.plural(c.expressions, "expression")]
            // Les fonctions ne sont citées que si le modèle en a (niveau de compatibilité 1702 ou plus).
            if c.functions > 0 { content.append(Format.plural(c.functions, "function")) }
            content.append(Format.plural(c.roles, "role"))
            rows.append(("Model content", content.joined(separator: ", ")))
        }
        let d = s.diagnostics
        rows.append(("Diagnostics", "\(Format.plural(d.errors, "error")), \(Format.plural(d.warnings, "warning")), \(Format.plural(d.infos, "info"))"))
        return rows
    }

    static func label(_ f: Report.Format) -> String { f == .pbir ? "PBIR" : "PBIR-Legacy" }
    static func label(_ f: SemanticModel.Format) -> String { f == .tmdl ? "TMDL" : "TMSL model.bim" }

    func text(_ s: ProjectSummary) -> String {
        var lines = [style.bold(s.name)]
        let rows = rows(s)
        let width = rows.map(\.0.count).max() ?? 0
        for (key, value) in rows {
            lines.append("  " + style.dim(key.padding(toLength: width, withPad: " ", startingAt: 0)) + "  " + value)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func markdown(_ s: ProjectSummary) -> String {
        var lines = ["# \(s.name)", "", "| | |", "|---|---|"]
        for (key, value) in rows(s) {
            lines.append("| \(key) | \(Format.cell(value)) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
