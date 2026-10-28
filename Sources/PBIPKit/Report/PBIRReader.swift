import Foundation

/// Lecteur du format PBIR (dossier `definition/` du rapport).
struct PBIRReader {
    let reader: FileReader
    let sink: DiagnosticSink

    func read(_ definition: URL) -> Report? {
        var report = Report(format: .pbir)

        let version = definition.appendingPathComponent("version.json")
        if FileReader.exists(version) {
            _ = reader.readJSON(version)
        } else {
            sink.error("pbir.missingVersion", "PBIR definition has no version.json.", url: definition)
        }

        let reportFile = definition.appendingPathComponent("report.json")
        if FileReader.exists(reportFile) {
            if let json = reader.readJSON(reportFile) {
                report.themeName = Self.themeName(json["themeCollection"])
                report.filters = filters(json["filterConfig"])
            }
        } else {
            sink.error("pbir.missingReport", "PBIR definition has no report.json.", url: definition)
        }

        let extensions = definition.appendingPathComponent("reportExtensions.json")
        if FileReader.exists(extensions), let json = reader.readJSON(extensions) {
            for entity in json["entities"]?.array ?? [] {
                guard let table = entity["name"]?.string else { continue }
                for measure in entity["measures"]?.array ?? [] {
                    guard let name = measure["name"]?.string else { continue }
                    report.extensionMeasures.append(ExtensionMeasure(
                        table: table, name: name, expression: BIMModelBuilder.expression(measure["expression"]) ?? ""))
                }
            }
        }

        report.pages = pages(definition.appendingPathComponent("pages"))
        report.bookmarks = bookmarks(definition.appendingPathComponent("bookmarks"))
        return report
    }

    /// Thème personnalisé s'il existe, sinon thème de base.
    static func themeName(_ collection: JSON?) -> String? {
        collection?.at("customTheme", "name")?.string ?? collection?.at("baseTheme", "name")?.string
    }

    func filters(_ filterConfig: JSON?) -> [FieldRef] {
        (filterConfig?["filters"]?.array ?? []).flatMap { FieldExtractor().fields(in: $0["field"], role: "filter") }
    }

    // MARK: - Pages

    func pages(_ folder: URL) -> [Page] {
        guard FileReader.isDirectory(folder) else {
            sink.error("pbir.missingPages", "PBIR definition has no pages/ folder.", url: folder)
            return []
        }
        var order: [String] = []
        let metadata = folder.appendingPathComponent("pages.json")
        if FileReader.exists(metadata), let json = reader.readJSON(metadata) {
            order = (json["pageOrder"]?.array ?? []).compactMap(\.string)
        }

        var pages: [Page] = []
        var unreadable = Set<String>()
        for pageFolder in FileReader.children(of: folder) where FileReader.isDirectory(pageFolder) {
            let file = pageFolder.appendingPathComponent("page.json")
            guard FileReader.exists(file) else {
                sink.warning("pbir.missingPageFile", "Page folder has no page.json; ignored.", url: pageFolder)
                continue
            }
            guard let json = reader.readJSON(file) else {
                unreadable.insert(pageFolder.lastPathComponent)
                continue
            }
            let id = json["name"]?.string ?? pageFolder.lastPathComponent
            pages.append(Page(
                id: id,
                displayName: json["displayName"]?.string ?? id,
                order: 0,
                width: json["width"]?.double ?? 0,
                height: json["height"]?.double ?? 0,
                visuals: visuals(pageFolder.appendingPathComponent("visuals")),
                filters: filters(json["filterConfig"])))
        }

        // `pageOrder` d'abord ; les pages absentes de la liste suivent, par nom de dossier.
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        pages = pages.enumerated().sorted { a, b in
            switch (rank[a.element.id], rank[b.element.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
        for i in pages.indices { pages[i].order = i }
        for id in order where !pages.contains(where: { $0.id == id }) && !unreadable.contains(id) {
            sink.warning("pbir.unknownPageInOrder", "pages.json lists page '\(id)' which does not exist.", url: metadata)
        }
        return pages
    }

    // MARK: - Visuels

    func visuals(_ folder: URL) -> [Visual] {
        guard FileReader.isDirectory(folder) else { return [] }
        var visuals: [Visual] = []
        for visualFolder in FileReader.children(of: folder) where FileReader.isDirectory(visualFolder) {
            let file = visualFolder.appendingPathComponent("visual.json")
            guard FileReader.exists(file) else {
                sink.warning("pbir.missingVisualFile", "Visual folder has no visual.json; ignored.", url: visualFolder)
                continue
            }
            guard let json = reader.readJSON(file) else { continue }
            visuals.append(visual(json, fallbackID: visualFolder.lastPathComponent))
        }
        return visuals.sorted { $0.id < $1.id }
    }

    func visual(_ json: JSON, fallbackID: String) -> Visual {
        let p = json["position"]
        let position = Position(x: p?["x"]?.double ?? 0, y: p?["y"]?.double ?? 0, z: p?["z"]?.double ?? 0,
                                width: p?["width"]?.double ?? 0, height: p?["height"]?.double ?? 0)
        let id = json["name"]?.string ?? fallbackID

        if let group = json["visualGroup"] {
            return Visual(id: id, type: "group", title: group["displayName"]?.string, position: position)
        }

        let visual = json["visual"]
        let query = visual?["query"]
        var roles: [String: [FieldRef]] = [:]
        for (role, state) in query?["queryState"]?.object ?? [:] {
            roles[role] = (state["projections"]?.array ?? []).flatMap { FieldExtractor().fields(in: $0["field"], role: role) }
        }
        let sorts = (query?.at("sortDefinition", "sort")?.array ?? []).flatMap { FieldExtractor().fields(in: $0["field"], role: "sort") }
        return Visual(
            id: id,
            type: visual?["visualType"]?.string ?? "unknown",
            title: FieldExtractor.title(visual?["visualContainerObjects"]),
            position: position,
            fields: FieldExtractor.assemble(roles: roles, filters: filters(json["filterConfig"]), sorts: sorts))
    }

    // MARK: - Signets

    func bookmarks(_ folder: URL) -> [Bookmark] {
        guard FileReader.isDirectory(folder) else { return [] }
        var byID: [String: Bookmark] = [:]
        for file in FileReader.children(of: folder) where file.lastPathComponent.hasSuffix(".bookmark.json") {
            guard let json = reader.readJSON(file) else { continue }
            let id = json["name"]?.string ?? String(file.lastPathComponent.dropLast(".bookmark.json".count))
            byID[id] = Bookmark(id: id, displayName: json["displayName"]?.string ?? id)
        }

        // Ordre de bookmarks.json (groupes aplatis), puis les autres par identifiant.
        // La forme exacte de `items` est tolérée : nom simple, objet `name`, `children` (docs/NOTES.md § 6).
        var order: [String] = []
        let metadata = folder.appendingPathComponent("bookmarks.json")
        if FileReader.exists(metadata), let json = reader.readJSON(metadata) {
            func walk(_ item: JSON) {
                if let name = item.string { order.append(name); return }
                if let children = item["children"]?.array {
                    children.forEach(walk)
                } else if let name = item["name"]?.string {
                    order.append(name)
                }
            }
            (json["items"]?.array ?? []).forEach(walk)
        }
        var result = order.compactMap { byID.removeValue(forKey: $0) }
        result += byID.values.sorted { $0.id < $1.id }
        return result
    }
}
