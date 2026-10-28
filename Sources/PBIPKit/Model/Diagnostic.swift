import Foundation

/// Un message produit pendant la lecture ou la validation d'un projet.
public struct Diagnostic: Codable, Hashable, Sendable {
    public enum Severity: String, Codable, Sendable, CaseIterable, Comparable {
        case error, warning, info

        /// `error` < `warning` < `info` : les plus graves d'abord quand on trie.
        var rank: Int {
            switch self {
            case .error: return 0
            case .warning: return 1
            case .info: return 2
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    public var severity: Severity
    /// Identifiant stable, utilisable pour filtrer (`json.invalid`, `report.unknownField`…).
    public var code: String
    public var message: String
    /// Chemin relatif à la racine du projet (voir docs/NOTES.md § 5).
    public var file: String?
    public var line: Int?

    public init(_ severity: Severity, code: String, message: String, file: String? = nil, line: Int? = nil) {
        self.severity = severity
        self.code = code
        self.message = message
        self.file = file
        self.line = line
    }
}

extension Array where Element == Diagnostic {
    public var hasErrors: Bool { contains { $0.severity == .error } }

    /// Ordre stable : gravité, fichier, ligne, code, message.
    public func sortedForOutput() -> [Diagnostic] {
        sorted { a, b in
            if a.severity != b.severity { return a.severity < b.severity }
            if (a.file ?? "") != (b.file ?? "") { return (a.file ?? "") < (b.file ?? "") }
            if (a.line ?? 0) != (b.line ?? 0) { return (a.line ?? 0) < (b.line ?? 0) }
            if a.code != b.code { return a.code < b.code }
            return a.message < b.message
        }
    }
}

/// Collecte les diagnostics en rendant les chemins relatifs à la racine du projet.
public final class DiagnosticSink {
    public private(set) var items: [Diagnostic] = []
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public func add(_ severity: Diagnostic.Severity, _ code: String, _ message: String, url: URL? = nil, line: Int? = nil) {
        items.append(Diagnostic(severity, code: code, message: message, file: url.map(relativePath), line: line))
    }

    public func error(_ code: String, _ message: String, url: URL? = nil, line: Int? = nil) {
        add(.error, code, message, url: url, line: line)
    }

    public func warning(_ code: String, _ message: String, url: URL? = nil, line: Int? = nil) {
        add(.warning, code, message, url: url, line: line)
    }

    public func info(_ code: String, _ message: String, url: URL? = nil, line: Int? = nil) {
        add(.info, code, message, url: url, line: line)
    }

    public func relativePath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }
}
