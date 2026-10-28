import Foundation

/// Extrait les références au modèle d'une expression de requête sémantique.
///
/// Formes reconnues (docs/NOTES.md § 2) : `Column`, `Measure`, `Aggregation` (on descend dans
/// `Expression`), `HierarchyLevel` (y compris sur `PropertyVariationSource`). Toute autre forme est
/// parcourue récursivement pour y trouver ces références (visual calculations, sparklines…).
struct FieldExtractor {
    /// Alias `Source` → `Entity` (PBIR-Legacy : déclarés dans `prototypeQuery.From`).
    var aliases: [String: String] = [:]

    init(from: JSON? = nil) {
        for item in from?.array ?? [] {
            if let name = item["Name"]?.string, let entity = item["Entity"]?.string {
                aliases[name] = entity
            }
        }
    }

    func fields(in expression: JSON?, role: String) -> [FieldRef] {
        guard let expression else { return [] }
        var out: [FieldRef] = []
        collect(expression, role: role, into: &out)
        return out
    }

    private func collect(_ json: JSON, role: String, into out: inout [FieldRef]) {
        switch json {
        case .object(let o):
            if let c = o["Column"], let name = c["Property"]?.string, let table = entity(c["Expression"]) {
                out.append(FieldRef(kind: .column, table: table, name: name, role: role))
                return
            }
            if let m = o["Measure"], let name = m["Property"]?.string, let table = entity(m["Expression"]) {
                out.append(FieldRef(kind: .measure, table: table, name: name, role: role))
                return
            }
            if let h = o["HierarchyLevel"], let field = hierarchyLevel(h, role: role) {
                out.append(field)
                return
            }
            // `Aggregation` et toute autre enveloppe : on descend dans les valeurs, dans un ordre stable.
            for key in o.keys.sorted() {
                collect(o[key]!, role: role, into: &out)
            }
        case .array(let items):
            for item in items { collect(item, role: role, into: &out) }
        default:
            break
        }
    }

    private func hierarchyLevel(_ h: JSON, role: String) -> FieldRef? {
        guard let level = h["Level"]?.string, let hierarchy = h.at("Expression", "Hierarchy") else { return nil }
        let hierarchyName = hierarchy["Hierarchy"]?.string
        let inner = hierarchy["Expression"]
        if let variation = inner?["PropertyVariationSource"] {
            // Hiérarchie de date automatique portée par une colonne.
            guard let table = entity(variation["Expression"]) else { return nil }
            return FieldRef(kind: .hierarchyLevel, table: table, name: level, role: role,
                            hierarchy: hierarchyName, variationColumn: variation["Property"]?.string)
        }
        guard let table = entity(inner) else { return nil }
        return FieldRef(kind: .hierarchyLevel, table: table, name: level, role: role, hierarchy: hierarchyName)
    }

    /// `{"SourceRef": {"Entity": …}}` ou `{"SourceRef": {"Source": alias}}`.
    private func entity(_ expression: JSON?) -> String? {
        guard let ref = expression?["SourceRef"] else { return nil }
        if let entity = ref["Entity"]?.string { return entity }
        if let source = ref["Source"]?.string { return aliases[source] }
        return nil
    }

    /// Ordre commun aux deux formats : rôles triés, puis filtres, puis tri ; doublons exacts retirés.
    static func assemble(roles: [String: [FieldRef]], filters: [FieldRef], sorts: [FieldRef]) -> [FieldRef] {
        var out: [FieldRef] = []
        var seen = Set<FieldRef>()
        let ordered = roles.keys.sorted().flatMap { roles[$0]! } + filters + sorts
        for field in ordered where seen.insert(field).inserted {
            out.append(field)
        }
        return out
    }

    /// Valeur d'un littéral de mise en forme : `'Texte d''exemple'` → `Texte d'exemple`.
    static func literalString(_ value: String?) -> String? {
        guard var v = value else { return nil }
        if v.count >= 2, v.hasPrefix("'"), v.hasSuffix("'") {
            v = String(v.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return v.isEmpty ? nil : v
    }

    /// Titre d'un visuel : `title[0].properties.text.expr.Literal.Value`.
    static func title(_ objects: JSON?) -> String? {
        literalString(objects?["title"]?[0]?.at("properties", "text", "expr", "Literal", "Value")?.string)
    }
}
