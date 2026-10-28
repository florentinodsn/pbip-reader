import Foundation

/// Rendu de `pbip model`.
public struct ModelRenderer {
    public var style: Style

    public init(style: Style) {
        self.style = style
    }

    /// Restreint le modèle à une table et aux relations qui la touchent.
    public static func filter(_ model: SemanticModel, table name: String?) -> SemanticModel? {
        guard let name else { return model }
        guard let table = model.table(named: name) else { return nil }
        var filtered = model
        filtered.tables = [table]
        filtered.relationships = model.relationships.filter {
            $0.from.table.caseInsensitiveCompare(table.name) == .orderedSame || $0.to.table.caseInsensitiveCompare(table.name) == .orderedSame
        }
        filtered.expressions = []
        filtered.functions = []
        filtered.roles = model.roles.filter { role in
            role.tablePermissions.contains { $0.table.caseInsensitiveCompare(table.name) == .orderedSame }
        }
        return filtered
    }

    public func render(_ model: SemanticModel, format: OutputFormat) -> String {
        switch format {
        case .json: return JSONOutput.encode(model)
        case .text: return text(model)
        case .markdown: return markdown(model)
        }
    }

    // MARK: - Texte

    func text(_ model: SemanticModel) -> String {
        var out: [String] = []
        for table in model.tables {
            var header = style.bold("Table \(table.name)")
            if table.isHidden { header += style.dim(" (hidden)") }
            out.append(header)
            if let d = table.description { out.append(Format.indent(d, "  ")) }

            if !table.columns.isEmpty {
                out.append("  " + style.cyan("Columns"))
                for c in table.columns {
                    var details = [c.dataType ?? "?"]
                    if c.isCalculated { details.append("calculated") } else if let s = c.sourceColumn { details.append("source: \(s)") }
                    if let f = c.formatString { details.append("format: \(f)") }
                    if c.isHidden { details.append("hidden") }
                    out.append("    \(c.name)  " + style.dim(details.joined(separator: " · ")))
                    if let e = c.expression { out.append(Format.indent(e, "      ")) }
                }
            }
            if !table.measures.isEmpty {
                out.append("  " + style.cyan("Measures"))
                for m in table.measures {
                    var details: [String] = []
                    if let f = m.formatString { details.append("format: \(f)") }
                    if let d = m.displayFolder { details.append("folder: \(d)") }
                    if m.isHidden { details.append("hidden") }
                    out.append("    \(m.name)" + (details.isEmpty ? "" : "  " + style.dim(details.joined(separator: " · "))))
                    if let d = m.description { out.append(Format.indent(style.dim("/// " + d.replacingOccurrences(of: "\n", with: "\n/// ")), "      ")) }
                    out.append(Format.indent(m.expression, "      "))
                }
            }
            if !table.hierarchies.isEmpty {
                out.append("  " + style.cyan("Hierarchies"))
                for h in table.hierarchies {
                    out.append("    \(h.name): " + h.levels.map(\.name).joined(separator: " › "))
                }
            }
            if !table.calculationItems.isEmpty {
                out.append("  " + style.cyan("Calculation items"))
                for item in table.calculationItems {
                    out.append("    \(item.name)")
                    out.append(Format.indent(item.expression, "      "))
                }
            }
            if !table.partitions.isEmpty {
                out.append("  " + style.cyan("Partitions"))
                for p in table.partitions {
                    out.append("    \(p.name)  " + style.dim([p.sourceKind, p.mode].compactMap { $0 }.joined(separator: " · ")))
                    if let e = p.expression { out.append(Format.indent(e, "      ")) }
                }
            }
            out.append("")
        }
        if !model.relationships.isEmpty {
            out.append(style.bold("Relationships"))
            for r in model.relationships {
                var details = [r.cardinality, r.crossFilteringBehavior]
                if !r.isActive { details.append("inactive") }
                out.append("  \(r.from.displayName) → \(r.to.displayName)  " + style.dim(details.joined(separator: " · ")))
            }
            out.append("")
        }
        if !model.expressions.isEmpty {
            out.append(style.bold("Expressions"))
            for e in model.expressions {
                out.append("  \(e.name)" + style.dim(e.isParameter ? "  parameter" : "  \(e.kind)"))
                out.append(Format.indent(e.expression, "    "))
            }
            out.append("")
        }
        if !model.functions.isEmpty {
            out.append(style.bold("Functions"))
            for f in model.functions {
                out.append("  \(f.name)" + (f.isHidden ? style.dim("  hidden") : ""))
                if let d = f.description { out.append(Format.indent(d, "    ")) }
                out.append(Format.indent(f.expression, "    "))
            }
            out.append("")
        }
        if !model.roles.isEmpty {
            out.append(style.bold("Roles"))
            for r in model.roles {
                out.append("  \(r.name)" + (r.modelPermission.map { style.dim("  \($0)") } ?? ""))
                for tp in r.tablePermissions {
                    out.append("    \(tp.table): \(tp.filterExpression ?? "")")
                }
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Markdown

    func markdown(_ model: SemanticModel) -> String {
        var out: [String] = []
        for table in model.tables {
            out.append("## \(table.name)\(table.isHidden ? " (hidden)" : "")")
            out.append("")
            if let d = table.description { out += [d, ""] }
            if !table.columns.isEmpty {
                out += ["### Columns", "", "| Name | Type | Source | Format | Hidden |", "|---|---|---|---|---|"]
                for c in table.columns {
                    let source = c.expression.map { "`\(Format.cell($0))`" } ?? Format.cell(c.sourceColumn)
                    out.append("| \(Format.cell(c.name)) | \(Format.cell(c.dataType)) | \(source) | \(Format.cell(c.formatString)) | \(c.isHidden ? "yes" : "") |")
                }
                out.append("")
            }
            if !table.measures.isEmpty {
                out += ["### Measures", ""]
                for m in table.measures {
                    var details: [String] = []
                    if let f = m.formatString { details.append("format `\(f)`") }
                    if let d = m.displayFolder { details.append("folder *\(d)*") }
                    if m.isHidden { details.append("hidden") }
                    out.append("#### \(m.name)")
                    out.append("")
                    if let d = m.description { out += [d, ""] }
                    if !details.isEmpty { out += [details.joined(separator: " · "), ""] }
                    out += ["```dax", m.expression, "```", ""]
                }
            }
            if !table.hierarchies.isEmpty {
                out += ["### Hierarchies", ""]
                out += table.hierarchies.map { "- **\($0.name)**: " + $0.levels.map(\.name).joined(separator: " › ") }
                out.append("")
            }
            if !table.partitions.isEmpty {
                out += ["### Partitions", ""]
                for p in table.partitions {
                    out.append("- **\(p.name)** (" + [p.sourceKind, p.mode].compactMap { $0 }.joined(separator: ", ") + ")")
                    if let e = p.expression {
                        out += ["", "```\(p.sourceKind == "m" ? "powerquery" : "dax")", e, "```"]
                    }
                }
                out.append("")
            }
        }
        if !model.relationships.isEmpty {
            out += ["## Relationships", "", "| From | To | Cardinality | Cross filter | Active |", "|---|---|---|---|---|"]
            for r in model.relationships {
                out.append("| \(Format.cell(r.from.displayName)) | \(Format.cell(r.to.displayName)) | \(r.cardinality) | \(r.crossFilteringBehavior) | \(r.isActive ? "yes" : "no") |")
            }
            out.append("")
        }
        if !model.expressions.isEmpty {
            out += ["## Expressions", ""]
            for e in model.expressions {
                out += ["### \(e.name)\(e.isParameter ? " (parameter)" : "")", "", "```powerquery", e.expression, "```", ""]
            }
        }
        if !model.functions.isEmpty {
            out += ["## Functions", ""]
            for f in model.functions {
                out += ["### \(f.name)\(f.isHidden ? " (hidden)" : "")", ""]
                if let d = f.description { out += [d, ""] }
                out += ["```dax", f.expression, "```", ""]
            }
        }
        if !model.roles.isEmpty {
            out += ["## Roles", ""]
            for r in model.roles {
                out.append("- **\(r.name)**" + (r.modelPermission.map { " (\($0))" } ?? ""))
                for tp in r.tablePermissions { out.append("  - \(tp.table): `\(tp.filterExpression ?? "")`") }
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }
}
