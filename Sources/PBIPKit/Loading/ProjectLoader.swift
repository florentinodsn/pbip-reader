import Foundation

public enum ProjectLoaderError: Error, CustomStringConvertible, Equatable {
    case notFound(String)
    case notAProject(String)

    public var description: String {
        switch self {
        case .notFound(let path): return "No such file or folder: \(path)"
        case .notAProject(let path): return "No .pbip file, .Report folder or .SemanticModel folder found in \(path)"
        }
    }
}

/// Point d'entrée : `.pbip` → `definition.pbir` → dossier du modèle.
///
/// Ne lève une erreur que si rien d'exploitable n'est trouvé. Tous les autres problèmes
/// deviennent des diagnostics du projet renvoyé.
public struct ProjectLoader {
    public init() {}

    public func load(_ url: URL) throws -> Project {
        let url = url.standardizedFileURL
        guard FileReader.exists(url) else { throw ProjectLoaderError.notFound(url.path) }
        let entry = try resolveEntry(url)
        let sink = DiagnosticSink(root: entry.root)
        let reader = FileReader(sink: sink)
        for message in entry.notes { sink.warning("project.ambiguous", message, url: entry.root) }

        var project = Project(name: entry.name, rootURL: entry.root)
        var reportURL = entry.report
        var modelURL = entry.model

        if let pbip = entry.pbip {
            reportURL = readPbip(pbip, reader: reader, sink: sink)
        }

        if let reportURL {
            project.reportPath = sink.relativePath(reportURL)
            project.reportDisplayName = platformDisplayName(reportURL, reader: reader)
            let pbir = reportURL.appendingPathComponent("definition.pbir")
            if FileReader.exists(pbir), let json = reader.readJSON(pbir) {
                let (reference, target) = readDatasetReference(json, reportURL: reportURL, pbir: pbir, sink: sink)
                project.datasetReference = reference
                if modelURL == nil { modelURL = target }
            } else if !FileReader.exists(pbir) {
                sink.error("pbir.missing", "Report folder has no definition.pbir.", url: reportURL)
            }
            project.report = ReportReader(reader: reader, sink: sink).read(reportURL)
        }

        if let modelURL {
            project.semanticModelPath = sink.relativePath(modelURL)
            project.semanticModelDisplayName = platformDisplayName(modelURL, reader: reader)
            project.semanticModel = SemanticModelReader(reader: reader, sink: sink).read(modelURL)
        }

        project.diagnostics = sink.items
        return project
    }

    // MARK: - Résolution du point d'entrée

    struct Entry {
        var name: String
        var root: URL
        var pbip: URL?
        var report: URL?
        var model: URL?
        var notes: [String] = []
    }

    func resolveEntry(_ url: URL) throws -> Entry {
        let lastName = url.lastPathComponent
        if !FileReader.isDirectory(url) {
            if url.pathExtension.lowercased() == "pbip" {
                return Entry(name: url.deletingPathExtension().lastPathComponent,
                             root: url.deletingLastPathComponent(), pbip: url)
            }
            if url.pathExtension.lowercased() == "pbir" {
                return try resolveEntry(url.deletingLastPathComponent())
            }
            if url.pathExtension.lowercased() == "pbism" || lastName == "model.bim" {
                return try resolveEntry(url.deletingLastPathComponent())
            }
            throw ProjectLoaderError.notAProject(url.path)
        }
        if let base = Self.stripSuffix(lastName, ".Report") {
            return Entry(name: base, root: url.deletingLastPathComponent(), report: url)
        }
        if let base = Self.stripSuffix(lastName, ".SemanticModel") ?? Self.stripSuffix(lastName, ".Dataset") {
            return Entry(name: base, root: url.deletingLastPathComponent(), model: url)
        }
        let children = FileReader.children(of: url)
        let pbips = children.filter { $0.pathExtension.lowercased() == "pbip" && !FileReader.isDirectory($0) }
        if let first = pbips.first {
            var entry = Entry(name: first.deletingPathExtension().lastPathComponent, root: url, pbip: first)
            if pbips.count > 1 {
                entry.notes.append("Folder contains \(pbips.count) .pbip files; using \(first.lastPathComponent). Pass the .pbip file explicitly to choose.")
            }
            return entry
        }
        let reports = children.filter { FileReader.isDirectory($0) && $0.lastPathComponent.hasSuffix(".Report") }
        if let first = reports.first {
            var entry = Entry(name: Self.stripSuffix(first.lastPathComponent, ".Report") ?? first.lastPathComponent,
                              root: url, report: first)
            if reports.count > 1 {
                entry.notes.append("Folder contains \(reports.count) report folders; using \(first.lastPathComponent).")
            }
            return entry
        }
        let models = children.filter {
            FileReader.isDirectory($0) && ($0.lastPathComponent.hasSuffix(".SemanticModel") || $0.lastPathComponent.hasSuffix(".Dataset"))
        }
        if let first = models.first {
            var entry = Entry(name: first.deletingPathExtension().lastPathComponent, root: url, model: first)
            if models.count > 1 {
                entry.notes.append("Folder contains \(models.count) semantic model folders; using \(first.lastPathComponent).")
            }
            return entry
        }
        throw ProjectLoaderError.notAProject(url.path)
    }

    static func stripSuffix(_ name: String, _ suffix: String) -> String? {
        guard name.count > suffix.count, name.hasSuffix(suffix) else { return nil }
        return String(name.dropLast(suffix.count))
    }

    // MARK: - Fichiers pointeurs

    /// `.pbip` : `artifacts[].report.path`, relatif au dossier du fichier.
    func readPbip(_ url: URL, reader: FileReader, sink: DiagnosticSink) -> URL? {
        guard let json = reader.readJSON(url) else { return nil }
        let paths = (json["artifacts"]?.array ?? []).compactMap { $0.at("report", "path")?.string }
        guard let path = paths.first else {
            sink.error("pbip.noReport", "No artifacts[].report.path in .pbip file.", url: url)
            return nil
        }
        if paths.count > 1 {
            sink.warning("pbip.multipleReports", "The .pbip file lists \(paths.count) reports; only the first one is read.", url: url)
        }
        let target = Self.resolve(path, against: url.deletingLastPathComponent())
        guard FileReader.isDirectory(target) else {
            sink.error("pbip.reportNotFound", "Report folder not found: \(path)", url: url)
            return nil
        }
        return target
    }

    /// `datasetReference` : exactement un de `byPath` / `byConnection`.
    func readDatasetReference(_ json: JSON, reportURL: URL, pbir: URL, sink: DiagnosticSink) -> (DatasetReference?, URL?) {
        guard let reference = json["datasetReference"]?.object else {
            sink.error("pbir.noDatasetReference", "definition.pbir has no datasetReference.", url: pbir)
            return (nil, nil)
        }
        let byPath = reference["byPath"].flatMap { $0 == .null ? nil : $0 }
        let byConnection = reference["byConnection"].flatMap { $0 == .null ? nil : $0 }
        if byPath != nil && byConnection != nil {
            sink.error("pbir.invalidDatasetReference", "datasetReference must contain byPath or byConnection, not both.", url: pbir)
        }
        if let byPath {
            guard let path = byPath["path"]?.string else {
                sink.error("pbir.invalidDatasetReference", "datasetReference.byPath has no path.", url: pbir)
                return (nil, nil)
            }
            if path.hasPrefix("/") || path.contains(":\\") {
                sink.warning("pbir.absolutePath", "datasetReference.byPath.path should be relative.", url: pbir)
            }
            let target = Self.resolve(path, against: reportURL)
            if !FileReader.isDirectory(target) {
                sink.error("pbir.modelNotFound", "Semantic model folder not found: \(path)", url: pbir)
                return (DatasetReference(kind: .byPath, path: path), nil)
            }
            return (DatasetReference(kind: .byPath, path: path), target)
        }
        if let byConnection {
            let connection = byConnection["connectionString"]?.string
            let name = connection.flatMap(Self.modelName(fromConnectionString:))
            sink.info("report.modelNotLocal",
                      "Report is connected to a published semantic model\(name.map { " (\($0))" } ?? ""); only the report is read.",
                      url: pbir)
            return (DatasetReference(kind: .byConnection, modelName: name, connectionString: connection), nil)
        }
        sink.error("pbir.invalidDatasetReference", "datasetReference must contain byPath or byConnection.", url: pbir)
        return (nil, nil)
    }

    /// Heuristique : `initial catalog=<nom>`, sinon `semanticmodelid=<id>` (voir docs/NOTES.md § 6).
    static func modelName(fromConnectionString connection: String) -> String? {
        var values: [String: String] = [:]
        for part in connection.split(separator: ";") {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = part[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var value = part[part.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values["initial catalog"] ?? values["semanticmodelid"]
    }

    func platformDisplayName(_ folder: URL, reader: FileReader) -> String? {
        let platform = folder.appendingPathComponent(".platform")
        guard FileReader.exists(platform) else { return nil }
        return reader.readJSON(platform)?.at("metadata", "displayName")?.string
    }

    /// Chemin relatif au format PBIP (séparateur `/`, `\` toléré).
    static func resolve(_ path: String, against base: URL) -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") { return URL(fileURLWithPath: normalized).standardizedFileURL }
        return base.appendingPathComponent(normalized).standardizedFileURL
    }
}
