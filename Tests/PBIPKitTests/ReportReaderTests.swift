import XCTest
@testable import PBIPKit

final class ReportReaderTests: XCTestCase {
    /// Critère de l'étape 6 : les deux formats donnent le même Report.
    func testVentesAndVentesLegacyProduceTheSameReport() throws {
        let pbir = try XCTUnwrap(Fixtures.load("Ventes").report)
        var legacy = try XCTUnwrap(Fixtures.load("VentesLegacy").report)
        XCTAssertEqual(pbir.format, .pbir)
        XCTAssertEqual(legacy.format, .legacy)
        legacy.format = .pbir

        XCTAssertEqual(pbir.pages.map(\.id), legacy.pages.map(\.id))
        for (a, b) in zip(pbir.pages, legacy.pages) {
            XCTAssertEqual(a.filters, b.filters, a.displayName)
            for (va, vb) in zip(a.visuals, b.visuals) {
                XCTAssertEqual(va, vb, "\(a.displayName) / \(va.id)")
            }
        }
        XCTAssertEqual(pbir.bookmarks, legacy.bookmarks)
        XCTAssertEqual(pbir.filters, legacy.filters)
        XCTAssertEqual(pbir, legacy)
    }

    func testVentesReportContent() throws {
        let report = try XCTUnwrap(Fixtures.load("Ventes").report)
        XCTAssertEqual(report.themeName, "CY24SU10")
        XCTAssertEqual(report.pages.map(\.displayName), ["Synthèse", "Détail produits"])
        XCTAssertEqual(report.pages.map(\.order), [0, 1])
        XCTAssertEqual(report.visualCount, 6)
        XCTAssertEqual(report.bookmarks, [Bookmark(id: "e3000000000000000001", displayName: "Vue 2025")])
        XCTAssertEqual(report.filters, [FieldRef(kind: .column, table: "Calendrier", name: "Année", role: "filter")])

        let synthese = report.pages[0]
        XCTAssertEqual(synthese.width, 1280)
        XCTAssertEqual(synthese.visuals[0].title, "Chiffre d'affaires HT", "apostrophe doubled in the literal")
        XCTAssertEqual(synthese.visuals[0].position, Position(x: 20, y: 20, z: 0, width: 280, height: 120))
        XCTAssertNil(synthese.visuals[1].title)

        let line = synthese.visuals[2]
        XCTAssertEqual(line.type, "lineChart")
        XCTAssertEqual(line.fields, [
            FieldRef(kind: .column, table: "Calendrier", name: "Année", role: "Category"),
            FieldRef(kind: .measure, table: "Ventes", name: "Total HT", role: "Y"),
            FieldRef(kind: .column, table: "Calendrier", name: "Année", role: "sort"),
        ])

        let detail = report.pages[1]
        XCTAssertEqual(detail.filters, [FieldRef(kind: .column, table: "Produits", name: "Catégorie", role: "filter")])
        XCTAssertEqual(detail.visuals[0].fields, [
            FieldRef(kind: .column, table: "Produits", name: "Libellé", role: "Values"),
            FieldRef(kind: .column, table: "Ventes", name: "Quantité", role: "Values"),
            FieldRef(kind: .measure, table: "Ventes", name: "Panier moyen", role: "Values"),
        ], "Aggregation resolves to its column")
        XCTAssertEqual(detail.visuals[1].fields, [
            FieldRef(kind: .hierarchyLevel, table: "Produits", name: "Catégorie", role: "Category", hierarchy: "Gamme"),
            FieldRef(kind: .measure, table: "Ventes", name: "Marge %", role: "Y"),
            FieldRef(kind: .column, table: "Produits", name: "Catégorie", role: "filter"),
        ])
    }

    func testPublieReadsExtensionMeasures() throws {
        let report = try XCTUnwrap(Fixtures.load("Publie").report)
        XCTAssertEqual(report.extensionMeasures, [ExtensionMeasure(table: "Ventes", name: "Total HT x2", expression: "[Total HT] * 2")])
        XCTAssertEqual(report.pages.first?.visuals.first?.fields.map(\.name), ["Total HT", "Total HT x2"])
    }

    func testInvalidJSONIsReportedAndTheRestIsRead() throws {
        let project = try Fixtures.load("JsonInvalide")
        let invalid = project.diagnostics(code: "json.invalid")
        XCTAssertEqual(invalid.count, 1)
        XCTAssertEqual(invalid.first?.file, "JsonInvalide.Report/definition/pages/a1c3e5f7a9b1c3e5f7a9/page.json")
        XCTAssertEqual(invalid.first?.line, 5)
        XCTAssertEqual(project.diagnostics(code: "encoding.bom").count, 1)
        XCTAssertEqual(project.diagnostics(code: "pbir.unknownPageInOrder"), [], "already reported as invalid JSON")
        XCTAssertEqual(project.report?.pages.map(\.displayName), ["Détail produits"])
    }

    func testUnknownSchemaMajorIsWarning() throws {
        let project = try Fixtures.load("RefCassee")
        let warnings = project.diagnostics(code: "schema.unknownVersion")
        XCTAssertEqual(warnings.map(\.file), ["RefCassee.Report/definition/report.json"])
        XCTAssertEqual(warnings.first?.severity, .warning)
    }

    // MARK: - Extraction des champs

    func testFieldExtractorResolvesAliasesAndVariations() throws {
        let from = try JSON.parse(#"[{"Name": "d", "Entity": "Dates", "Type": 0}]"#)
        let extractor = FieldExtractor(from: from)
        let variation = try JSON.parse("""
        {"HierarchyLevel": {"Expression": {"Hierarchy": {"Expression": {"PropertyVariationSource": {
            "Expression": {"SourceRef": {"Source": "d"}}, "Name": "Variation", "Property": "Date"}},
            "Hierarchy": "Date Hierarchy"}}, "Level": "Year"}}
        """)
        XCTAssertEqual(extractor.fields(in: variation, role: "Category"), [
            FieldRef(kind: .hierarchyLevel, table: "Dates", name: "Year", role: "Category",
                     hierarchy: "Date Hierarchy", variationColumn: "Date"),
        ])
    }

    func testFieldExtractorFindsNestedFields() throws {
        let nested = try JSON.parse("""
        {"SparklineData": {"Measure": {"Measure": {"Expression": {"SourceRef": {"Entity": "S"}}, "Property": "M"}},
                           "Groupings": [{"Column": {"Expression": {"SourceRef": {"Entity": "D"}}, "Property": "Day"}}]}}
        """)
        XCTAssertEqual(FieldExtractor().fields(in: nested, role: "Y").map(\.displayName), ["D[Day]", "S[M]"])
    }

    func testLiteralString() {
        XCTAssertEqual(FieldExtractor.literalString("'L''été'"), "L'été")
        XCTAssertNil(FieldExtractor.literalString("''"))
        XCTAssertEqual(FieldExtractor.literalString("12D"), "12D")
    }
}
