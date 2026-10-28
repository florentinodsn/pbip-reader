import Foundation
@testable import PBIPKit

/// Accès aux projets fictifs de Tests/Fixtures, localisés depuis ce fichier source.
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static func url(_ name: String) -> URL {
        root.appendingPathComponent(name).appendingPathComponent("\(name).pbip")
    }

    static func load(_ name: String) throws -> Project {
        try ProjectLoader().load(url(name))
    }
}

extension Project {
    func diagnostics(code: String) -> [Diagnostic] {
        diagnostics.filter { $0.code == code }
    }
}
