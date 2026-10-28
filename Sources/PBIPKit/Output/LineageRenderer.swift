import Foundation

/// Rendu de `pbip lineage`.
public struct LineageRenderer {
    public var style: Style

    public init(style: Style) {
        self.style = style
    }

    /// Restreint le lignage aux objets portant ce nom, et aux visuels qui les utilisent.
    public static func filter(_ lineage: Lineage, name: String?) -> Lineage? {
        guard let name else { return lineage }
        let entries = lineage.entries.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard !entries.isEmpty else { return nil }
        let targets = Set(entries.map(\.displayName))
        func matches(_ f: Lineage.ResolvedField) -> Bool { f.target.map(targets.contains) ?? false }
        return Lineage(entries: entries,
                       visuals: lineage.visuals.filter { $0.fields.contains(where: matches) },
                       filters: lineage.filters.filter(matches))
    }

    public func render(_ lineage: Lineage, format: OutputFormat) -> String {
        switch format {
        case .json: return JSONOutput.encode(lineage)
        case .text: return text(lineage)
        case .markdown: return markdown(lineage)
        }
    }

    /// En texte et Markdown, on omet les colonnes que rien n'utilise.
    static func shown(_ lineage: Lineage) -> [Lineage.Entry] {
        lineage.entries.filter { $0.kind != .column || !$0.usedBy.isEmpty || !$0.referencedBy.isEmpty || !$0.exists }
    }

    static func status(_ s: Lineage.ResolvedField.Status) -> String {
        switch s {
        case .ok: return "ok"
        case .unknownTable: return "unknown table"
        case .unknownField: return "unknown field"
        case .kindMismatch: return "kind mismatch"
        case .notChecked: return "not checked"
        }
    }

    func text(_ lineage: Lineage) -> String {
        var out: [String] = [style.bold("Model objects → report"), ""]
        for e in Self.shown(lineage) {
            var header = "\(e.displayName) " + style.dim("(\(e.kind.rawValue))")
            if !e.exists { header += " " + style.red("missing from model") }
            out.append(header)
            if e.usedBy.isEmpty && e.referencedBy.isEmpty {
                out.append("  " + style.yellow("not used"))
            }
            for u in e.usedBy { out.append("  used by        " + u.label) }
            for r in e.referencedBy { out.append("  referenced by  " + r) }
            for r in e.references { out.append("  references     " + r) }
        }
        out += ["", style.bold("Report → model objects"), ""]
        for v in lineage.visuals {
            let title = v.visualTitle.map { " \"\($0)\"" } ?? " \(v.visualId)"
            out.append("\(v.page) › \(v.visualType)\(title)")
            for f in v.fields { out.append(fieldLine(f)) }
        }
        if !lineage.filters.isEmpty {
            out.append("Filters")
            for f in lineage.filters { out.append(fieldLine(f)) }
        }
        return out.joined(separator: "\n") + "\n"
    }

    func fieldLine(_ f: Lineage.ResolvedField) -> String {
        let mark = f.status == .ok ? style.green("✓") : (f.status == .notChecked ? style.dim("·") : style.red("✗"))
        var line = "  \(mark) \(f.field.role): \(f.field.displayName)"
        if let target = f.target, target != f.field.displayName { line += " → \(target)" }
        if f.status != .ok { line += style.dim(" (\(Self.status(f.status)))") }
        return line
    }

    func markdown(_ lineage: Lineage) -> String {
        var out = ["## Model objects → report", "", "| Object | Kind | Used by | Referenced by | References |", "|---|---|---|---|---|"]
        for e in Self.shown(lineage) {
            let name = Format.cell(e.displayName) + (e.exists ? "" : " ⚠️ missing")
            out.append("| \(name) | \(e.kind.rawValue) | \(Format.cell(e.usedBy.map(\.label).joined(separator: "\n"))) | \(Format.cell(e.referencedBy.joined(separator: "\n"))) | \(Format.cell(e.references.joined(separator: "\n"))) |")
        }
        out += ["", "## Report → model objects", "", "| Page | Visual | Role | Field | Status |", "|---|---|---|---|---|"]
        for v in lineage.visuals {
            let visual = v.visualType + (v.visualTitle.map { " \"\($0)\"" } ?? "")
            for f in v.fields {
                out.append("| \(Format.cell(v.page)) | \(Format.cell(visual)) | \(Format.cell(f.field.role)) | \(Format.cell(f.field.displayName)) | \(Self.status(f.status)) |")
            }
        }
        return out.joined(separator: "\n") + "\n"
    }
}

/// Rendu de `pbip validate`.
public struct ValidationRenderer {
    public struct Output: Codable, Equatable, Sendable {
        public var errors: Int
        public var warnings: Int
        public var infos: Int
        public var diagnostics: [Diagnostic]
    }

    public var style: Style

    public init(style: Style) {
        self.style = style
    }

    public func render(_ diagnostics: [Diagnostic], format: OutputFormat) -> String {
        let output = Output(errors: diagnostics.filter { $0.severity == .error }.count,
                            warnings: diagnostics.filter { $0.severity == .warning }.count,
                            infos: diagnostics.filter { $0.severity == .info }.count,
                            diagnostics: diagnostics)
        switch format {
        case .json: return JSONOutput.encode(output)
        case .text: return text(output)
        case .markdown: return markdown(output)
        }
    }

    static func location(_ d: Diagnostic) -> String {
        [d.file, d.line.map(String.init)].compactMap { $0 }.joined(separator: ":")
    }

    func text(_ o: Output) -> String {
        var out = o.diagnostics.map { d in
            "\(style.severity(d.severity)) \(style.dim(d.code)) \(Self.location(d))\n         \(d.message)"
        }
        let summary = "\(Format.plural(o.errors, "error")), \(Format.plural(o.warnings, "warning")), \(Format.plural(o.infos, "info"))"
        out.append(o.errors > 0 ? style.red(summary) : style.green(summary))
        return out.joined(separator: "\n") + "\n"
    }

    func markdown(_ o: Output) -> String {
        var out = ["**\(Format.plural(o.errors, "error")), \(Format.plural(o.warnings, "warning")), \(Format.plural(o.infos, "info"))**", ""]
        if !o.diagnostics.isEmpty {
            out += ["| Severity | Code | Location | Message |", "|---|---|---|---|"]
            for d in o.diagnostics {
                out.append("| \(d.severity.rawValue) | `\(d.code)` | \(Format.cell(Self.location(d))) | \(Format.cell(d.message)) |")
            }
        }
        return out.joined(separator: "\n") + "\n"
    }
}
