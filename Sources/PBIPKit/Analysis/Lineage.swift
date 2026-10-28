import Foundation

/// Lignage entre les visuels et le modèle, dans les deux sens.
public struct Lineage: Codable, Equatable, Sendable {
    /// Endroit du rapport où un objet est utilisé.
    public struct Usage: Codable, Hashable, Sendable {
        public enum Scope: String, Codable, Sendable {
            case report, page, visual
        }

        public var scope: Scope
        public var pageId: String?
        public var page: String?
        public var visualId: String?
        public var visualType: String?
        public var visualTitle: String?
        public var role: String

        /// `Page › type "titre" (rôle)`.
        public var label: String {
            var parts: [String] = []
            switch scope {
            case .report:
                parts.append("report filter")
            case .page:
                parts.append("\(page ?? "?") › page filter")
            case .visual:
                var visual = visualType ?? "visual"
                if let visualTitle { visual += " \"\(visualTitle)\"" } else if let visualId { visual += " \(visualId)" }
                parts.append("\(page ?? "?") › \(visual)")
            }
            return parts.joined() + " (\(role))"
        }
    }

    /// Un objet du modèle (ou du rapport) et ce qui l'utilise.
    public struct Entry: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case measure, column, extensionMeasure
        }

        public var kind: Kind
        public var table: String
        public var name: String
        /// Faux pour un objet référencé par le rapport mais absent du modèle.
        public var exists: Bool
        public var usedBy: [Usage]
        /// Mesures et colonnes calculées dont le DAX référence cet objet (`Table[Nom]`).
        public var referencedBy: [String]
        /// Objets référencés par le DAX de cet objet.
        public var references: [String]

        public var displayName: String { "\(table)[\(name)]" }
    }

    public struct ResolvedField: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable {
            case ok, unknownTable, unknownField, kindMismatch, notChecked
        }

        public var field: FieldRef
        public var status: Status
        /// Objet du modèle atteint (un niveau de hiérarchie mène à sa colonne).
        public var target: String?
    }

    public struct VisualEntry: Codable, Equatable, Sendable {
        public var pageId: String
        public var page: String
        public var visualId: String
        public var visualType: String
        public var visualTitle: String?
        public var fields: [ResolvedField]
    }

    public var entries: [Entry]
    public var visuals: [VisualEntry]
    /// Filtres de rapport et de page, résolus comme les champs des visuels.
    public var filters: [ResolvedField]

    public init(entries: [Entry] = [], visuals: [VisualEntry] = [], filters: [ResolvedField] = []) {
        self.entries = entries
        self.visuals = visuals
        self.filters = filters
    }

    /// Mesures du modèle qu'aucun visuel ni filtre n'atteint, directement ou par le DAX d'une autre mesure.
    public var unusedMeasures: [Entry] {
        let byKey = Dictionary(entries.map { (Self.key($0.table, $0.name), $0) }, uniquingKeysWith: { a, _ in a })
        var reached = Set<String>()
        var queue = entries.filter { !$0.usedBy.isEmpty }.map { Self.key($0.table, $0.name) }
        while let key = queue.popLast() {
            guard reached.insert(key).inserted, let entry = byKey[key] else { continue }
            queue += entry.references.compactMap(Self.parseDisplayName).map { Self.key($0.0, $0.1) }
        }
        return entries.filter { $0.kind == .measure && $0.exists && !reached.contains(Self.key($0.table, $0.name)) }
    }

    static func key(_ table: String, _ name: String) -> String {
        "\(table.lowercased())\u{1F}\(name.lowercased())"
    }

    /// `Table[Nom]` → (Table, Nom). Les noms de table ne contiennent pas de `[`.
    static func parseDisplayName(_ text: String) -> (String, String)? {
        guard let open = text.firstIndex(of: "["), text.hasSuffix("]") else { return nil }
        return (String(text[..<open]), String(text[text.index(after: open)..<text.index(before: text.endIndex)]))
    }
}

/// Construit le lignage d'un projet.
public enum LineageBuilder {
    public static func build(_ project: Project) -> Lineage {
        let model = project.semanticModel
        let report = project.report
        let extensions = report?.extensionMeasures ?? []

        // 1. Inventaire des objets.
        var entries: [String: Lineage.Entry] = [:]
        var order: [String] = []
        func add(_ kind: Lineage.Entry.Kind, _ table: String, _ name: String, exists: Bool) -> String {
            let key = Lineage.key(table, name)
            if entries[key] == nil {
                entries[key] = Lineage.Entry(kind: kind, table: table, name: name, exists: exists,
                                             usedBy: [], referencedBy: [], references: [])
                order.append(key)
            }
            return key
        }
        for table in model?.tables ?? [] {
            for m in table.measures { _ = add(.measure, table.name, m.name, exists: true) }
            for c in table.columns { _ = add(.column, table.name, c.name, exists: true) }
        }
        for m in extensions { _ = add(.extensionMeasure, m.table, m.name, exists: true) }

        // 2. Dépendances DAX (mesures, colonnes calculées, mesures de rapport).
        var daxSources: [(table: String, name: String, expression: String)] = []
        for table in model?.tables ?? [] {
            for m in table.measures { daxSources.append((table.name, m.name, m.expression)) }
            for c in table.columns { if let e = c.expression { daxSources.append((table.name, c.name, e)) } }
        }
        for m in extensions { daxSources.append((m.table, m.name, m.expression)) }

        // Un objet qui appelle une fonction dépend aussi de ce que le corps de la fonction référence,
        // fonctions imbriquées comprises.
        func functionReferences(_ expression: String, seen: inout Set<String>) -> [DAXReference] {
            var refs: [DAXReference] = []
            for call in DAXScanner.calls(in: expression) {
                guard let f = model?.function(named: call), seen.insert(f.name.lowercased()).inserted else { continue }
                refs += DAXScanner.references(in: f.expression) + functionReferences(f.expression, seen: &seen)
            }
            return refs
        }

        for source in daxSources {
            let sourceKey = Lineage.key(source.table, source.name)
            var references: [String] = []
            var seen = Set<String>()
            let refs = DAXScanner.references(in: source.expression) + functionReferences(source.expression, seen: &seen)
            for ref in refs {
                guard let target = resolveDAX(ref, from: source.table, model: model, extensions: extensions) else { continue }
                let targetKey = Lineage.key(target.table, target.name)
                guard targetKey != sourceKey, entries[targetKey] != nil else { continue }
                let targetName = entries[targetKey]!.displayName
                if !references.contains(targetName) { references.append(targetName) }
                let sourceName = entries[sourceKey]?.displayName ?? "\(source.table)[\(source.name)]"
                if !entries[targetKey]!.referencedBy.contains(sourceName) {
                    entries[targetKey]!.referencedBy.append(sourceName)
                }
            }
            entries[sourceKey]?.references = references
        }

        // 3. Utilisations dans le rapport.
        var visuals: [Lineage.VisualEntry] = []
        var filters: [Lineage.ResolvedField] = []
        func use(_ field: FieldRef, _ usage: Lineage.Usage) -> Lineage.ResolvedField {
            let resolved = resolve(field, model: model, extensions: extensions)
            if let target = resolved.target, let (table, name) = Lineage.parseDisplayName(target) {
                let kind: Lineage.Entry.Kind = field.kind == .measure && resolved.status != .kindMismatch ? .measure : .column
                let key = add(kind, table, name, exists: resolved.status == .ok || resolved.status == .kindMismatch)
                if !entries[key]!.usedBy.contains(usage) { entries[key]!.usedBy.append(usage) }
            }
            return resolved
        }
        if let report {
            for f in report.filters {
                filters.append(use(f, Lineage.Usage(scope: .report, role: f.role)))
            }
            for page in report.pages {
                for f in page.filters {
                    filters.append(use(f, Lineage.Usage(scope: .page, pageId: page.id, page: page.displayName, role: f.role)))
                }
                for visual in page.visuals {
                    let fields = visual.fields.map { f in
                        use(f, Lineage.Usage(scope: .visual, pageId: page.id, page: page.displayName, visualId: visual.id,
                                             visualType: visual.type, visualTitle: visual.title, role: f.role))
                    }
                    visuals.append(Lineage.VisualEntry(pageId: page.id, page: page.displayName, visualId: visual.id,
                                                       visualType: visual.type, visualTitle: visual.title, fields: fields))
                }
            }
        }
        return Lineage(entries: order.compactMap { entries[$0] }, visuals: visuals, filters: filters)
    }

    /// Résout un champ du rapport sur le modèle local et les mesures de rapport.
    static func resolve(_ field: FieldRef, model: SemanticModel?, extensions: [ExtensionMeasure]) -> Lineage.ResolvedField {
        let extensionMatch = extensions.first {
            $0.table.caseInsensitiveCompare(field.table) == .orderedSame && $0.name.caseInsensitiveCompare(field.name) == .orderedSame
        }
        guard let model else {
            // Modèle publié : seules les mesures de rapport sont vérifiables.
            if field.kind == .measure, let m = extensionMatch {
                return .init(field: field, status: .ok, target: "\(m.table)[\(m.name)]")
            }
            return .init(field: field, status: .notChecked, target: "\(field.table)[\(field.variationColumn ?? field.name)]")
        }
        guard let table = model.table(named: field.table) else {
            if field.kind == .measure, let m = extensionMatch {
                return .init(field: field, status: .ok, target: "\(m.table)[\(m.name)]")
            }
            return .init(field: field, status: .unknownTable, target: nil)
        }
        switch field.kind {
        case .column:
            if let c = table.column(named: field.name) { return .init(field: field, status: .ok, target: "\(table.name)[\(c.name)]") }
            if let m = table.measure(named: field.name) { return .init(field: field, status: .kindMismatch, target: "\(table.name)[\(m.name)]") }
            return .init(field: field, status: .unknownField, target: nil)
        case .measure:
            if let m = table.measure(named: field.name) { return .init(field: field, status: .ok, target: "\(table.name)[\(m.name)]") }
            if let m = extensionMatch { return .init(field: field, status: .ok, target: "\(m.table)[\(m.name)]") }
            if let c = table.column(named: field.name) { return .init(field: field, status: .kindMismatch, target: "\(table.name)[\(c.name)]") }
            return .init(field: field, status: .unknownField, target: nil)
        case .hierarchyLevel:
            if let column = field.variationColumn {
                // Hiérarchie de date automatique : elle vit dans une table locale ; on vérifie la colonne.
                guard let c = table.column(named: column) else { return .init(field: field, status: .unknownField, target: nil) }
                return .init(field: field, status: .ok, target: "\(table.name)[\(c.name)]")
            }
            guard let hierarchy = table.hierarchy(named: field.hierarchy ?? ""),
                  let level = hierarchy.levels.first(where: { $0.name.caseInsensitiveCompare(field.name) == .orderedSame }),
                  let c = table.column(named: level.column) else {
                return .init(field: field, status: .unknownField, target: nil)
            }
            return .init(field: field, status: .ok, target: "\(table.name)[\(c.name)]")
        }
    }

    /// `[Nom]` seul : une mesure (noms uniques dans le modèle), sinon une colonne de la même table.
    static func resolveDAX(_ ref: DAXReference, from table: String, model: SemanticModel?,
                           extensions: [ExtensionMeasure]) -> (table: String, name: String)? {
        if let tableName = ref.table {
            guard let t = model?.table(named: tableName) else {
                if let m = extensions.first(where: { $0.table == tableName && $0.name == ref.name }) { return (m.table, m.name) }
                return nil
            }
            if let m = t.measure(named: ref.name) { return (t.name, m.name) }
            if let c = t.column(named: ref.name) { return (t.name, c.name) }
            return nil
        }
        for t in model?.tables ?? [] {
            if let m = t.measure(named: ref.name) { return (t.name, m.name) }
        }
        if let m = extensions.first(where: { $0.name.caseInsensitiveCompare(ref.name) == .orderedSame }) { return (m.table, m.name) }
        if let t = model?.table(named: table), let c = t.column(named: ref.name) { return (t.name, c.name) }
        return nil
    }
}
