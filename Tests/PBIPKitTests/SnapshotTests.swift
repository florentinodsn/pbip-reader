import XCTest
@testable import PBIPKit

/// Sorties JSON et Markdown comparées à des fichiers de référence (Tests/Snapshots).
/// `PBIP_RECORD_SNAPSHOTS=1 swift test` réécrit les références.
final class SnapshotTests: XCTestCase {
    static let directory = Fixtures.root.deletingLastPathComponent().appendingPathComponent("Snapshots")
    let style = Style(color: false)

    func assertSnapshot(_ actual: String, _ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = Self.directory.appendingPathComponent(name)
        let record = ProcessInfo.processInfo.environment["PBIP_RECORD_SNAPSHOTS"] == "1"
        if record || !FileManager.default.fileExists(atPath: url.path) {
            try Data(actual.utf8).write(to: url)
            if !record { XCTFail("Snapshot \(name) was missing and has been recorded; run the tests again.", file: file, line: line) }
            return
        }
        let expected = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(actual, expected, "Snapshot \(name) differs. Re-record with PBIP_RECORD_SNAPSHOTS=1 if intended.", file: file, line: line)
    }

    func outputs(_ name: String, format: OutputFormat) throws -> [String: String] {
        let project = try Fixtures.load(name)
        var out: [String: String] = [
            "info": InfoRenderer(style: style).render(project, format: format),
            "validate": ValidationRenderer(style: style).render(Validator.validate(project), format: format),
            "lineage": LineageRenderer(style: style).render(LineageBuilder.build(project), format: format),
        ]
        if let model = project.semanticModel { out["model"] = ModelRenderer(style: style).render(model, format: format) }
        if let report = project.report { out["report"] = ReportRenderer(style: style).render(report, format: format) }
        return out
    }

    func testVentesJSON() throws {
        for (command, text) in try outputs("Ventes", format: .json).sorted(by: { $0.key < $1.key }) {
            try assertSnapshot(text, "Ventes.\(command).json")
        }
    }

    func testVentesMarkdown() throws {
        for (command, text) in try outputs("Ventes", format: .markdown).sorted(by: { $0.key < $1.key }) {
            try assertSnapshot(text, "Ventes.\(command).md")
        }
    }

    func testErrorCasesJSON() throws {
        for name in ["Publie", "RefCassee", "Conflit"] {
            try assertSnapshot(try outputs(name, format: .json)["validate"]!, "\(name).validate.json")
        }
    }

    /// Le legacy donne exactement la même sortie, au format près.
    func testLegacyJSONMatchesPBIR() throws {
        let pbir = try outputs("Ventes", format: .json)
        let legacy = try outputs("VentesLegacy", format: .json)
        XCTAssertEqual(legacy["lineage"], pbir["lineage"])
        XCTAssertEqual(legacy["report"], pbir["report"]?.replacingOccurrences(of: "\"format\" : \"pbir\"", with: "\"format\" : \"legacy\""))
        XCTAssertEqual(legacy["model"], pbir["model"]?.replacingOccurrences(of: "\"format\" : \"tmdl\"", with: "\"format\" : \"bim\""))
    }

    func testJSONIsStableAndKeysAreSorted() throws {
        let a = try outputs("Ventes", format: .json)
        let b = try outputs("Ventes", format: .json)
        XCTAssertEqual(a, b)
        // Les clés de premier niveau du résumé apparaissent dans l'ordre alphabétique.
        let keys = a["info"]!.split(separator: "\n").filter { $0.hasPrefix("  \"") }
            .map { $0.dropFirst(3).prefix { $0 != "\"" } }.map(String.init)
        XCTAssertEqual(keys, keys.sorted())
        XCTAssertFalse(a["model"]!.contains("\\/"), "slashes are not escaped")
    }
}
