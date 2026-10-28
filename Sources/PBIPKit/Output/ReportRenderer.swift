import Foundation

/// Rendu de `pbip report`.
public struct ReportRenderer {
    public var style: Style

    public init(style: Style) {
        self.style = style
    }

    /// Restreint le rapport à une page, cherchée par identifiant puis par nom affiché.
    public static func filter(_ report: Report, page: String?) -> Report? {
        guard let page else { return report }
        let match = report.pages.first { $0.id == page }
            ?? report.pages.first { $0.displayName.caseInsensitiveCompare(page) == .orderedSame }
        guard let match else { return nil }
        var filtered = report
        filtered.pages = [match]
        return filtered
    }

    public func render(_ report: Report, format: OutputFormat) -> String {
        switch format {
        case .json: return JSONOutput.encode(report)
        case .text: return text(report)
        case .markdown: return markdown(report)
        }
    }

    static func fieldLabel(_ f: FieldRef) -> String {
        let kind = f.kind == .hierarchyLevel ? "level" : f.kind.rawValue
        return "\(f.displayName) (\(kind))"
    }

    /// Champs groupés par rôle, dans l'ordre du modèle.
    static func groupedFields(_ fields: [FieldRef]) -> [(String, [FieldRef])] {
        var groups: [(String, [FieldRef])] = []
        for f in fields {
            if let i = groups.firstIndex(where: { $0.0 == f.role }) {
                groups[i].1.append(f)
            } else {
                groups.append((f.role, [f]))
            }
        }
        return groups
    }

    func text(_ report: Report) -> String {
        var out: [String] = []
        var header = [report.format == .pbir ? "PBIR" : "PBIR-Legacy"]
        if let theme = report.themeName { header.append("theme \(theme)") }
        out.append(style.dim(header.joined(separator: " · ")))
        if !report.filters.isEmpty {
            out.append("Report filters: " + report.filters.map(\.displayName).joined(separator: ", "))
        }
        for m in report.extensionMeasures {
            out.append("Report measure \(m.table)[\(m.name)] = \(m.expression)")
        }
        out.append("")
        for page in report.pages {
            out.append(style.bold("Page \(page.order + 1) · \(page.displayName)") + style.dim("  \(page.id) · \(Format.number(page.width))×\(Format.number(page.height))"))
            if !page.filters.isEmpty {
                out.append("  Page filters: " + page.filters.map(\.displayName).joined(separator: ", "))
            }
            for v in page.visuals {
                let title = v.title.map { " \"\($0)\"" } ?? ""
                let p = v.position
                out.append("  " + style.cyan(v.type) + title + style.dim("  \(v.id) · (\(Format.number(p.x)), \(Format.number(p.y))) \(Format.number(p.width))×\(Format.number(p.height))"))
                for (role, fields) in Self.groupedFields(v.fields) {
                    out.append("    \(role): " + fields.map(Self.fieldLabel).joined(separator: ", "))
                }
            }
            out.append("")
        }
        if !report.bookmarks.isEmpty {
            out.append(style.bold("Bookmarks"))
            out += report.bookmarks.map { "  \($0.displayName)" + style.dim("  \($0.id)") }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    func markdown(_ report: Report) -> String {
        var out: [String] = []
        var header = ["Format: \(report.format == .pbir ? "PBIR" : "PBIR-Legacy")"]
        if let theme = report.themeName { header.append("theme: \(theme)") }
        out += [header.joined(separator: " · "), ""]
        if !report.filters.isEmpty {
            out += ["Report filters: " + report.filters.map { "`\($0.displayName)`" }.joined(separator: ", "), ""]
        }
        for page in report.pages {
            out += ["## \(page.order + 1). \(page.displayName)", "",
                    "`\(page.id)` · \(Format.number(page.width))×\(Format.number(page.height))", ""]
            if !page.filters.isEmpty {
                out += ["Page filters: " + page.filters.map { "`\($0.displayName)`" }.joined(separator: ", "), ""]
            }
            if !page.visuals.isEmpty {
                out += ["| Visual | Title | Position | Fields |", "|---|---|---|---|"]
                for v in page.visuals {
                    let p = v.position
                    let fields = Self.groupedFields(v.fields).map { role, fields in
                        "\(role): " + fields.map { "`\($0.displayName)`" }.joined(separator: ", ")
                    }.joined(separator: "<br>")
                    out.append("| \(Format.cell(v.type)) | \(Format.cell(v.title)) | (\(Format.number(p.x)), \(Format.number(p.y))) \(Format.number(p.width))×\(Format.number(p.height)) | \(fields.replacingOccurrences(of: "|", with: "\\|")) |")
                }
                out.append("")
            }
        }
        if !report.bookmarks.isEmpty {
            out += ["## Bookmarks", ""] + report.bookmarks.map { "- \($0.displayName)" } + [""]
        }
        return out.joined(separator: "\n")
    }
}
