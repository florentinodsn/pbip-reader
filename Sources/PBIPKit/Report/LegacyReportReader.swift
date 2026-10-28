import Foundation

/// Lecteur du format PBIR-Legacy (`report.json` unique).
///
/// Ce format n'est pas documenté publiquement ; la structure lue est décrite dans docs/NOTES.md § 2.
/// Plusieurs propriétés (`config`, `filters`, `visualContainers[].config`…) sont des chaînes
/// contenant du JSON, décodées une seconde fois.
struct LegacyReportReader {
    let reader: FileReader
    let sink: DiagnosticSink

    func read(_ url: URL) -> Report? {
        guard let json = reader.readJSON(url) else { return nil }
        var report = Report(format: .legacy)

        let config = reader.decodeEmbedded(json["config"], url: url, context: "report config")
        report.themeName = PBIRReader.themeName(config?["themeCollection"])
        report.bookmarks = bookmarks(config?["bookmarks"])
        report.extensionMeasures = extensionMeasures(config?["modelExtensions"])
        report.filters = filters(json["filters"], url: url, context: "report filters")

        let sections = json["sections"]?.array ?? []
        var pages: [(ordinal: Int, page: Page)] = []
        for (index, section) in sections.enumerated() {
            let id = section["name"]?.string ?? "section\(index)"
            let page = Page(
                id: id,
                displayName: section["displayName"]?.string ?? id,
                order: 0,
                width: section["width"]?.double ?? 0,
                height: section["height"]?.double ?? 0,
                visuals: (section["visualContainers"]?.array ?? []).enumerated()
                    .compactMap { visual($1, fallbackID: "\(id)-visual\($0)", url: url) }
                    .sorted { $0.id < $1.id },
                filters: filters(section["filters"], url: url, context: "page '\(id)' filters"))
            pages.append((section["ordinal"]?.int ?? index, page))
        }
        report.pages = pages.enumerated()
            .sorted { ($0.element.ordinal, $0.offset) < ($1.element.ordinal, $1.offset) }
            .map(\.element.page)
        for i in report.pages.indices { report.pages[i].order = i }
        return report
    }

    func filters(_ value: JSON?, url: URL, context: String) -> [FieldRef] {
        let decoded = reader.decodeEmbedded(value, url: url, context: context)
        return (decoded?.array ?? []).flatMap { filter in
            // Le legacy nomme le champ `expression` ; on accepte aussi `field` comme en PBIR.
            FieldExtractor().fields(in: filter["expression"] ?? filter["field"], role: "filter")
        }
    }

    func visual(_ container: JSON, fallbackID: String, url: URL) -> Visual? {
        let config = reader.decodeEmbedded(container["config"], url: url, context: "visual config")
        let id = config?["name"]?.string ?? fallbackID
        let p = config?["layouts"]?[0]?["position"] ?? container
        let position = Position(x: p["x"]?.double ?? 0, y: p["y"]?.double ?? 0, z: p["z"]?.double ?? 0,
                                width: p["width"]?.double ?? 0, height: p["height"]?.double ?? 0)

        if let group = config?["singleVisualGroup"] {
            return Visual(id: id, type: "group", title: group["displayName"]?.string, position: position)
        }
        let single = config?["singleVisual"]
        let query = single?["prototypeQuery"]
        let extractor = FieldExtractor(from: query?["From"])

        // `projections` ne donne que des `queryRef` ; le champ réel est dans `Select`, au même `Name`.
        var selectByName: [String: JSON] = [:]
        for item in query?["Select"]?.array ?? [] {
            if let name = item["Name"]?.string { selectByName[name] = item }
        }
        var roles: [String: [FieldRef]] = [:]
        for (role, projections) in single?["projections"]?.object ?? [:] {
            roles[role] = (projections.array ?? []).flatMap { projection -> [FieldRef] in
                guard let ref = projection["queryRef"]?.string else { return [] }
                guard let select = selectByName[ref] else {
                    sink.warning("legacy.unresolvedProjection",
                                 "Visual '\(id)': projection '\(ref)' has no matching prototypeQuery.Select entry.", url: url)
                    return []
                }
                return extractor.fields(in: select, role: role)
            }
        }
        let sorts = (query?["OrderBy"]?.array ?? []).flatMap { extractor.fields(in: $0["Expression"], role: "sort") }
        return Visual(
            id: id,
            type: single?["visualType"]?.string ?? "unknown",
            title: FieldExtractor.title(single?["vcObjects"]),
            position: position,
            fields: FieldExtractor.assemble(
                roles: roles,
                filters: filters(container["filters"], url: url, context: "visual '\(id)' filters"),
                sorts: sorts))
    }

    /// Signets : les groupes portent `children` ; on aplatit dans l'ordre.
    func bookmarks(_ value: JSON?) -> [Bookmark] {
        var out: [Bookmark] = []
        func walk(_ item: JSON) {
            if let children = item["children"]?.array {
                children.forEach(walk)
            } else if let id = item["name"]?.string {
                out.append(Bookmark(id: id, displayName: item["displayName"]?.string ?? id))
            }
        }
        (value?.array ?? []).forEach(walk)
        return out
    }

    /// Mesures de rapport : `modelExtensions[].entities[].measures[]`.
    func extensionMeasures(_ value: JSON?) -> [ExtensionMeasure] {
        var out: [ExtensionMeasure] = []
        for ext in value?.array ?? [] {
            for entity in ext["entities"]?.array ?? [] {
                guard let table = entity["name"]?.string else { continue }
                for measure in entity["measures"]?.array ?? [] {
                    guard let name = measure["name"]?.string else { continue }
                    out.append(ExtensionMeasure(table: table, name: name,
                                                expression: BIMModelBuilder.expression(measure["expression"]) ?? ""))
                }
            }
        }
        return out
    }
}
