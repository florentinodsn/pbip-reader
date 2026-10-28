import Foundation

/// Lit un dossier `definition/` TMDL et le convertit en `SemanticModel`.
struct TMDLModelReader {
    let reader: FileReader
    let sink: DiagnosticSink

    func read(_ folder: URL) -> SemanticModel? {
        var nodes: [TMDLNode] = []
        for url in Self.tmdlFiles(in: folder) {
            guard let text = reader.readText(url) else { continue }
            var parser = TMDLParser(text: text, file: sink.relativePath(url)) { severity, code, message, line in
                sink.add(severity, code, message, url: url, line: line)
            }
            nodes.append(contentsOf: parser.parse())
        }
        return TMDLModelBuilder(sink: sink, root: sink.root).build(nodes)
    }

    /// Tous les `.tmdl` du dossier, racine d'abord puis sous-dossiers, par ordre alphabétique.
    static func tmdlFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "tmdl" }
        let base = folder.standardizedFileURL.path
        func relative(_ url: URL) -> String { String(url.standardizedFileURL.path.dropFirst(base.count)) }
        return files.sorted { a, b in
            let ra = relative(a), rb = relative(b)
            let da = ra.filter { $0 == "/" }.count, db = rb.filter { $0 == "/" }.count
            return da != db ? da < db : ra < rb
        }
    }
}

/// Conversion de l'arbre TMDL (éventuellement réparti sur plusieurs fichiers) en modèle objet.
public struct TMDLModelBuilder {
    let sink: DiagnosticSink
    let root: URL

    public init(sink: DiagnosticSink, root: URL) {
        self.sink = sink
        self.root = root
    }

    private func url(_ node: TMDLNode) -> URL { root.appendingPathComponent(node.file) }

    public func build(_ nodes: [TMDLNode]) -> SemanticModel {
        var model = SemanticModel(format: .tmdl)
        var tableNodes: [String: [TMDLNode]] = [:]
        var tableOrder: [String] = []
        var tableRefs: [TMDLNode] = []

        func visit(_ node: TMDLNode) {
            if node.isRef {
                if node.kind == "table" { tableRefs.append(node) }
                return
            }
            switch node.kind {
            case "database":
                if let level = node.property("compatibilityLevel").flatMap(Int.init) {
                    model.compatibilityLevel = level
                }
                node.children.forEach(visit)
            case "model":
                if let culture = node.property("culture") { model.culture = culture }
                node.children.forEach(visit)
            case "table":
                guard let name = node.name else { return }
                let key = name.lowercased()
                if tableNodes[key] == nil { tableOrder.append(key) }
                tableNodes[key, default: []].append(node)
            case "relationship":
                if let r = relationship(node) { model.relationships.append(r) }
            case "expression":
                guard let name = node.name else { return }
                model.expressions.append(NamedExpression(
                    name: name, kind: node.property("kind") ?? "m",
                    expression: node.defaultValue ?? "", description: node.description))
            case "role":
                guard let name = node.name else { return }
                model.roles.append(Role(
                    name: name,
                    modelPermission: node.property("modelPermission").map { Enums.canonical($0, Enums.modelPermission) },
                    tablePermissions: node.children("tablePermission").compactMap { tp in
                        tp.name.map { Role.TablePermission(table: $0, filterExpression: tp.defaultValue) }
                    }))
            case "perspective":
                if let name = node.name { model.perspectives.append(name) }
            case "cultureinfo", "culture":
                if let name = node.name, !model.cultures.contains(name) { model.cultures.append(name) }
            default:
                break
            }
        }
        nodes.forEach(visit)

        // Ordre : d'abord les `ref table`, puis les tables non référencées, dans l'ordre de lecture.
        var ordered: [String] = []
        for ref in tableRefs {
            guard let name = ref.name else { continue }
            let key = name.lowercased()
            if tableNodes[key] == nil {
                sink.info("tmdl.refWithoutObject", "ref table '\(name)' has no matching table definition; ignored.",
                          url: url(ref), line: ref.line)
            } else if !ordered.contains(key) {
                ordered.append(key)
            }
        }
        ordered += tableOrder.filter { !ordered.contains($0) }
        model.tables = ordered.compactMap { tableNodes[$0].map(table) }
        return model
    }

    // MARK: - Tables

    func table(_ parts: [TMDLNode]) -> Table {
        let first = parts[0]
        var table = Table(name: first.name ?? "")
        table.description = parts.compactMap(\.description).first
        table.isHidden = parts.contains { $0.flag("isHidden") == true }

        var seen: [String: Set<String>] = [:]
        func unique(_ kind: String, _ name: String, _ node: TMDLNode) -> Bool {
            if seen[kind, default: []].insert(name.lowercased()).inserted { return true }
            sink.error("tmdl.duplicateObject", "Duplicate \(kind) '\(name)' in table '\(table.name)'.", url: url(node), line: node.line)
            return false
        }

        for part in parts {
            for child in part.children where !child.isRef {
                switch child.kind {
                case "column":
                    guard let name = child.name, unique("column", name, child) else { continue }
                    table.columns.append(column(child, name: name))
                case "measure":
                    guard let name = child.name, unique("measure", name, child) else { continue }
                    table.measures.append(Measure(
                        name: name,
                        expression: child.defaultValue ?? child.property("expression") ?? "",
                        formatString: child.property("formatString"),
                        displayFolder: child.property("displayFolder"),
                        description: child.description,
                        isHidden: child.flag("isHidden") ?? false))
                case "partition":
                    guard let name = child.name, unique("partition", name, child) else { continue }
                    table.partitions.append(partition(child, name: name))
                case "hierarchy":
                    guard let name = child.name, unique("hierarchy", name, child) else { continue }
                    table.hierarchies.append(Hierarchy(name: name, levels: child.children("level").compactMap { level in
                        level.name.map { Hierarchy.Level(name: $0, column: TMDLName.unquoteReference(level.property("column") ?? $0)) }
                    }))
                case "calculationgroup":
                    for item in child.children("calculationItem") {
                        guard let name = item.name else { continue }
                        table.calculationItems.append(CalculationItem(
                            name: name, expression: item.defaultValue ?? item.property("expression") ?? ""))
                    }
                default:
                    break
                }
            }
        }
        return table
    }

    func column(_ node: TMDLNode, name: String) -> Column {
        let expression = node.defaultValue.flatMap { $0.isEmpty ? nil : $0 }
        return Column(
            name: name,
            dataType: node.property("dataType").map { Enums.canonical($0, Enums.dataType) },
            sourceColumn: node.property("sourceColumn"),
            expression: expression,
            formatString: node.property("formatString"),
            displayFolder: node.property("displayFolder"),
            description: node.description,
            isHidden: node.flag("isHidden") ?? false)
    }

    func partition(_ node: TMDLNode, name: String) -> Partition {
        let kind = node.defaultValue?.trimmingCharacters(in: .whitespaces).lowercased()
        let expression = node.property("source") ?? node.property("query") ?? node.property("entityName")
        return Partition(
            name: name,
            mode: node.property("mode").map { Enums.canonical($0, Enums.partitionMode) },
            sourceKind: kind.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown",
            expression: expression)
    }

    // MARK: - Relations

    func relationship(_ node: TMDLNode) -> Relationship? {
        guard let id = node.name else { return nil }
        guard let from = columnRef(node.property("fromColumn"), node: node, property: "fromColumn"),
              let to = columnRef(node.property("toColumn"), node: node, property: "toColumn") else { return nil }
        return Relationship(
            id: id, from: from, to: to,
            fromCardinality: node.property("fromCardinality").map { Enums.canonical($0, Enums.cardinality) } ?? "many",
            toCardinality: node.property("toCardinality").map { Enums.canonical($0, Enums.cardinality) } ?? "one",
            crossFilteringBehavior: node.property("crossFilteringBehavior").map { Enums.canonical($0, Enums.crossFiltering) } ?? "oneDirection",
            isActive: node.flag("isActive") ?? true)
    }

    func columnRef(_ text: String?, node: TMDLNode, property: String) -> ColumnRef? {
        guard let text else {
            sink.error("tmdl.invalidRelationship", "Relationship '\(node.name ?? "?")' has no \(property).", url: url(node), line: node.line)
            return nil
        }
        let parts = TMDLName.splitQualified(text)
        guard parts.count == 2 else {
            sink.error("tmdl.invalidRelationship", "Relationship '\(node.name ?? "?")': \(property) must be Table.Column, got '\(text)'.",
                       url: url(node), line: node.line)
            return nil
        }
        return ColumnRef(table: parts[0], column: parts[1])
    }
}

/// Valeurs d'énumération TOM, normalisées en camelCase (la lecture TMDL est insensible à la casse).
enum Enums {
    static let dataType = ["string", "int64", "double", "dateTime", "decimal", "boolean", "binary", "variant", "unknown", "automatic"]
    static let cardinality = ["one", "many", "none"]
    static let crossFiltering = ["oneDirection", "bothDirections", "automatic"]
    static let partitionMode = ["import", "directQuery", "dual", "directLake", "default", "push"]
    static let modelPermission = ["none", "read", "readRefresh", "refresh", "administrator"]

    static func canonical(_ value: String, _ known: [String]) -> String {
        known.first { $0.caseInsensitiveCompare(value) == .orderedSame } ?? value
    }
}
