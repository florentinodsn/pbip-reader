import Foundation

/// Lecture des fichiers texte et JSON d'un projet, sans jamais les modifier.
struct FileReader {
    let sink: DiagnosticSink

    static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Lit un fichier UTF-8. Un BOM est accepté mais signalé (Desktop écrit sans BOM).
    func readText(_ url: URL) -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            sink.error("io.unreadable", "Cannot read file: \(error.localizedDescription)", url: url)
            return nil
        }
        var bytes = data
        if bytes.starts(with: FileReader.utf8BOM) {
            sink.warning("encoding.bom", "File starts with a UTF-8 BOM; PBIP files should be UTF-8 without BOM.", url: url)
            bytes = bytes.dropFirst(3)
        }
        guard let text = String(data: bytes, encoding: .utf8) else {
            sink.error("encoding.invalidUTF8", "File is not valid UTF-8.", url: url)
            return nil
        }
        return text
    }

    /// Lit un fichier JSON et vérifie la version de son `$schema`.
    func readJSON(_ url: URL) -> JSON? {
        guard let text = readText(url) else { return nil }
        let json: JSON
        do {
            json = try JSON.parse(text)
        } catch {
            sink.error("json.invalid", "Invalid JSON: \(FileReader.describe(error))", url: url, line: FileReader.line(of: error))
            return nil
        }
        SchemaVersion.check(json, url: url, sink: sink)
        return json
    }

    /// Décode une chaîne contenant du JSON (format PBIR-Legacy). Un objet déjà décodé est renvoyé tel quel.
    func decodeEmbedded(_ value: JSON?, url: URL, context: String) -> JSON? {
        guard let value else { return nil }
        switch value {
        case .string(let s):
            if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            do {
                return try JSON.parse(s)
            } catch {
                sink.error("legacy.invalidEmbeddedJSON", "Invalid JSON string in \(context): \(FileReader.describe(error))", url: url)
                return nil
            }
        case .null:
            return nil
        default:
            return value
        }
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if let debug = ns.userInfo["NSDebugDescription"] as? String { return debug }
        return ns.localizedDescription
    }

    /// Foundation indique la ligne dans le message (« around line 5, column 0 »).
    static func line(of error: Error) -> Int? {
        let text = describe(error)
        guard let range = text.range(of: #"line (\d+)"#, options: .regularExpression) else { return nil }
        return Int(text[range].dropFirst(5))
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Contenu d'un dossier, trié, sans fichiers cachés.
    static func children(of url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// Lecture tolérante de la version portée par `$schema`.
enum SchemaVersion {
    /// Dernière version majeure connue par nom de schéma (vérifié sur GitHub, voir docs/NOTES.md § 6).
    static let knownMajor: [String: Int] = [
        "pbip/pbipProperties": 1,
        "item/report/definitionProperties": 2,
        "item/report/definition/report": 3,
        "item/report/definition/page": 2,
        "item/report/definition/pagesMetadata": 1,
        "item/report/definition/visualContainer": 2,
        "item/report/definition/versionMetadata": 1,
        "item/report/definition/bookmark": 2,
        "item/report/definition/bookmarksMetadata": 1,
        "item/report/definition/reportExtension": 1,
        "item/semanticModel/definitionProperties": 1,
        "gitIntegration/platformProperties": 2,
    ]

    struct Parsed: Equatable {
        var name: String
        var major: Int
        var minor: Int
        var patch: Int
    }

    /// `…/json-schemas/fabric/<nom>/<x.y.z>/schema.json` → nom et version.
    static func parse(_ url: String) -> Parsed? {
        guard let marker = url.range(of: "/json-schemas/fabric/") else { return nil }
        var parts = url[marker.upperBound...].split(separator: "/").map(String.init)
        guard parts.count >= 3, parts.removeLast() == "schema.json" else { return nil }
        let numbers = parts.removeLast().split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        return Parsed(name: parts.joined(separator: "/"), major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    static func check(_ json: JSON, url: URL, sink: DiagnosticSink) {
        guard let schema = json["$schema"]?.string, let parsed = parse(schema),
              let known = knownMajor[parsed.name] else { return }
        if parsed.major > known {
            sink.warning("schema.unknownVersion",
                         "Schema \(parsed.name) version \(parsed.major).\(parsed.minor).\(parsed.patch) is newer than the known major version \(known); reading anyway.",
                         url: url)
        }
    }
}
