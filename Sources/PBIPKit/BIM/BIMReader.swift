import Foundation

/// Lit un `model.bim` (TMSL, objet `Database`) et le convertit en `SemanticModel`.
struct BIMReader {
    let reader: FileReader
    let sink: DiagnosticSink

    func read(_ url: URL) -> SemanticModel? {
        guard let json = reader.readJSON(url) else { return nil }
        return BIMModelBuilder(sink: sink, url: url).build(json)
    }
}

public struct BIMModelBuilder {
    let sink: DiagnosticSink
    let url: URL

    public init(sink: DiagnosticSink, url: URL) {
        self.sink = sink
        self.url = url
    }

    public func build(_ json: JSON) -> SemanticModel {
        var model = SemanticModel(format: .bim)
        model.compatibilityLevel = json["compatibilityLevel"]?.int
        guard let m = json["model"] else {
            sink.error("bim.noModel", "model.bim has no 'model' object.", url: url)
            return model
        }
        model.culture = m["culture"]?.string
        model.tables = (m["tables"]?.array ?? []).compactMap(table)
        model.relationships = (m["relationships"]?.array ?? []).compactMap(relationship)
        model.expressions = (m["expressions"]?.array ?? []).compactMap { e in
            guard let name = e["name"]?.string else { return nil }
            return NamedExpression(name: name, kind: e["kind"]?.string ?? "m",
                                   expression: Self.expression(e["expression"]) ?? "",
                                   description: e["description"]?.string)
        }
        model.functions = (m["functions"]?.array ?? []).compactMap { f in
            guard let name = f["name"]?.string else { return nil }
            return UserFunction(name: name, expression: Self.expression(f["expression"]) ?? "",
                                description: f["description"]?.string, isHidden: f["isHidden"]?.bool ?? false)
        }
        model.roles = (m["roles"]?.array ?? []).compactMap { r in
            guard let name = r["name"]?.string else { return nil }
            return Role(name: name,
                        modelPermission: r["modelPermission"]?.string.map { Enums.canonical($0, Enums.modelPermission) },
                        tablePermissions: (r["tablePermissions"]?.array ?? []).compactMap { tp in
                            tp["name"]?.string.map { Role.TablePermission(table: $0, filterExpression: Self.expression(tp["filterExpression"])) }
                        })
        }
        model.cultures = (m["cultures"]?.array ?? []).compactMap { $0["name"]?.string }
        model.perspectives = (m["perspectives"]?.array ?? []).compactMap { $0["name"]?.string }
        return model
    }

    /// TMSL accepte une expression en chaîne ou en tableau de lignes.
    static func expression(_ value: JSON?) -> String? {
        switch value {
        case .string(let s)?: return ExpressionText.normalize(s)
        case .array(let lines)?: return ExpressionText.normalize(lines.compactMap(\.string).joined(separator: "\n"))
        default: return nil
        }
    }

    func table(_ t: JSON) -> Table? {
        guard let name = t["name"]?.string else { return nil }
        var table = Table(name: name, description: t["description"]?.string, isHidden: t["isHidden"]?.bool ?? false)
        for c in t["columns"]?.array ?? [] {
            guard let columnName = c["name"]?.string else { continue }
            // Colonne technique du moteur, absente du TMDL : on l'ignore pour que les deux formats coïncident.
            if c["type"]?.string?.lowercased() == "rownumber" { continue }
            table.columns.append(Column(
                name: columnName,
                dataType: c["dataType"]?.string.map { Enums.canonical($0, Enums.dataType) },
                sourceColumn: c["sourceColumn"]?.string,
                expression: c["type"]?.string?.lowercased() == "calculated" ? Self.expression(c["expression"]) : nil,
                formatString: c["formatString"]?.string,
                displayFolder: c["displayFolder"]?.string,
                description: c["description"]?.string,
                isHidden: c["isHidden"]?.bool ?? false))
        }
        for me in t["measures"]?.array ?? [] {
            guard let measureName = me["name"]?.string else { continue }
            table.measures.append(Measure(
                name: measureName,
                expression: Self.expression(me["expression"]) ?? "",
                formatString: me["formatString"]?.string,
                displayFolder: me["displayFolder"]?.string,
                description: me["description"]?.string,
                isHidden: me["isHidden"]?.bool ?? false))
        }
        for p in t["partitions"]?.array ?? [] {
            guard let partitionName = p["name"]?.string else { continue }
            let source = p["source"]
            table.partitions.append(Partition(
                name: partitionName,
                mode: p["mode"]?.string.map { Enums.canonical($0, Enums.partitionMode) },
                sourceKind: source?["type"]?.string?.lowercased() ?? "unknown",
                expression: Self.expression(source?["expression"]) ?? Self.expression(source?["query"]) ?? source?["entityName"]?.string))
        }
        for h in t["hierarchies"]?.array ?? [] {
            guard let hierarchyName = h["name"]?.string else { continue }
            let levels = (h["levels"]?.array ?? [])
                .sorted { ($0["ordinal"]?.int ?? 0) < ($1["ordinal"]?.int ?? 0) }
                .compactMap { l -> Hierarchy.Level? in
                    guard let levelName = l["name"]?.string else { return nil }
                    return Hierarchy.Level(name: levelName, column: l["column"]?.string ?? levelName)
                }
            table.hierarchies.append(Hierarchy(name: hierarchyName, levels: levels))
        }
        for item in t.at("calculationGroup", "calculationItems")?.array ?? [] {
            guard let itemName = item["name"]?.string else { continue }
            table.calculationItems.append(CalculationItem(name: itemName, expression: Self.expression(item["expression"]) ?? ""))
        }
        return table
    }

    func relationship(_ r: JSON) -> Relationship? {
        guard let fromTable = r["fromTable"]?.string, let fromColumn = r["fromColumn"]?.string,
              let toTable = r["toTable"]?.string, let toColumn = r["toColumn"]?.string else {
            sink.error("bim.invalidRelationship", "Relationship '\(r["name"]?.string ?? "?")' is missing a table or column.", url: url)
            return nil
        }
        return Relationship(
            id: r["name"]?.string ?? "",
            from: ColumnRef(table: fromTable, column: fromColumn),
            to: ColumnRef(table: toTable, column: toColumn),
            fromCardinality: r["fromCardinality"]?.string.map { Enums.canonical($0, Enums.cardinality) } ?? "many",
            toCardinality: r["toCardinality"]?.string.map { Enums.canonical($0, Enums.cardinality) } ?? "one",
            crossFilteringBehavior: r["crossFilteringBehavior"]?.string.map { Enums.canonical($0, Enums.crossFiltering) } ?? "oneDirection",
            isActive: r["isActive"]?.bool ?? true)
    }
}
