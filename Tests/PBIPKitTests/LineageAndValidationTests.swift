import XCTest
@testable import PBIPKit

final class LineageAndValidationTests: XCTestCase {
    // MARK: - DAX

    func testDAXScannerFindsQualifiedAndBareReferences() {
        let refs = DAXScanner.references(in: """
        // [Commentaire] ignoré
        VAR x = SUM('Ventes Lignes'[Montant HT]) + Ventes[Quantité] /* [Bloc] */
        RETURN DIVIDE([Total HT], x) & "[pas une référence]" & 'L''an'[Date]
        """)
        XCTAssertEqual(refs, [
            DAXReference(table: "Ventes Lignes", name: "Montant HT"),
            DAXReference(table: "Ventes", name: "Quantité"),
            DAXReference(table: nil, name: "Total HT"),
            DAXReference(table: "L'an", name: "Date"),
        ])
    }

    func testDAXScannerFindsCallsOutsideStringsAndComments() {
        let calls = DAXScanner.calls(in: """
        // Commentaire ( ignoré
        ROUND ( Outils.Arrondir([Total HT]) , 2 ) + Outils.arrondir (1) & "Faux(1)" + 'Table (x)'[Col] /* Bloc(2) */ + Ventes[Prix (HT)]
        """)
        XCTAssertEqual(calls, ["ROUND", "Outils.Arrondir"])
    }

    func testUserFunctionSignature() throws {
        let f = UserFunction(name: "F", expression: "( a, b : SCALAR INT64  VAL, c : STRING = \"x, (y)\", d : ANYREF ) =>\n\tIF ( a, b )")
        let s = try XCTUnwrap(f.signature)
        XCTAssertEqual(s.parameters, [
            UserFunction.Parameter(name: "a", typeHint: nil, defaultExpression: nil),
            UserFunction.Parameter(name: "b", typeHint: "SCALAR INT64 VAL", defaultExpression: nil),
            UserFunction.Parameter(name: "c", typeHint: "STRING", defaultExpression: "\"x, (y)\""),
            UserFunction.Parameter(name: "d", typeHint: "ANYREF", defaultExpression: nil),
        ])
        XCTAssertEqual(s.body, "IF ( a, b )")
        XCTAssertEqual(UserFunction(name: "R", expression: "() => RANDBETWEEN ( 10, 100 )").signature?.parameters, [])
        XCTAssertNil(UserFunction(name: "X", expression: "SUM(1)").signature)
    }

    func testDAXScannerHandlesEscapedBracket() {
        XCTAssertEqual(DAXScanner.references(in: "[Taux ]]x]]]"), [DAXReference(table: nil, name: "Taux ]x]")])
    }

    // MARK: - Lignage

    func testVentesLineage() throws {
        let lineage = LineageBuilder.build(try Fixtures.load("Ventes"))
        func entry(_ name: String) -> Lineage.Entry? { lineage.entries.first { $0.name == name } }

        let total = try XCTUnwrap(entry("Total HT"))
        XCTAssertEqual(total.usedBy.map(\.label), [
            "Synthèse › card \"Chiffre d'affaires HT\" (Values)",
            "Synthèse › lineChart \"Évolution du CA\" (Y)",
        ])
        XCTAssertEqual(total.references, ["Ventes[Montant HT]"])
        XCTAssertEqual(total.referencedBy, ["Ventes[Panier moyen]", "Ventes[Total HT N-1]", "Ventes[Marge %]"])

        // Un niveau de hiérarchie compte comme une utilisation de sa colonne.
        let categorie = try XCTUnwrap(lineage.entries.first { $0.displayName == "Produits[Catégorie]" })
        XCTAssertEqual(categorie.usedBy.map(\.role), ["filter", "Category", "filter"])
        XCTAssertEqual(categorie.usedBy.map(\.scope), [.page, .visual, .visual])

        // Colonne calculée : références DAX vers d'autres colonnes.
        XCTAssertEqual(entry("Montant HT")?.references, ["Ventes[Quantité]", "Ventes[Prix unitaire]"])

        XCTAssertEqual(lineage.visuals.count, 6)
        XCTAssertTrue(lineage.visuals.allSatisfy { $0.fields.allSatisfy { $0.status == .ok } })
        XCTAssertEqual(lineage.unusedMeasures.map(\.displayName), ["Ventes[Total HT N-1]"])
    }

    func testLegacyLineageEqualsPBIRLineage() throws {
        XCTAssertEqual(LineageBuilder.build(try Fixtures.load("Ventes")),
                       LineageBuilder.build(try Fixtures.load("VentesLegacy")))
    }

    func testPublieFieldsAreNotCheckedExceptReportMeasures() throws {
        let lineage = LineageBuilder.build(try Fixtures.load("Publie"))
        XCTAssertEqual(lineage.visuals.first?.fields.map(\.status), [.notChecked, .ok])
        XCTAssertEqual(lineage.entries.first { $0.name == "Total HT x2" }?.kind, .extensionMeasure)
    }

    func testFilterByName() throws {
        let lineage = LineageBuilder.build(try Fixtures.load("Ventes"))
        let filtered = try XCTUnwrap(LineageRenderer.filter(lineage, name: "panier moyen"))
        XCTAssertEqual(filtered.entries.map(\.displayName), ["Ventes[Panier moyen]"])
        XCTAssertEqual(filtered.visuals.map(\.visualTitle), ["Ventes par produit"])
        XCTAssertNil(LineageRenderer.filter(lineage, name: "Nope"))
    }

    // MARK: - Validation

    func testVentesHasOnlyTheUnusedMeasureInfo() throws {
        for name in ["Ventes", "VentesLegacy"] {
            let diagnostics = Validator.validate(try Fixtures.load(name))
            XCTAssertEqual(diagnostics.map(\.code), ["model.unusedMeasure"], name)
            XCTAssertFalse(diagnostics.hasErrors)
        }
    }

    func testRefCasseeDiagnostics() throws {
        let diagnostics = Validator.validate(try Fixtures.load("RefCassee"))
        XCTAssertEqual(diagnostics.map(\.code), [
            "report.unknownField", "report.unknownTable", "model.brokenRelationship", "model.brokenRelationship",
            "report.kindMismatch", "schema.unknownVersion", "tmdl.unknownKeyword",
            "model.unusedMeasure", "tmdl.refWithoutObject",
        ])
        XCTAssertTrue(diagnostics.hasErrors)
        let visual = "RefCassee.Report/definition/pages/p0000000000000000001/visuals/v0000000000000000001/visual.json"
        XCTAssertEqual(diagnostics[0].file, visual)
        XCTAssertTrue(diagnostics[0].message.contains("Ventes[Total TTC]"))
        XCTAssertTrue(diagnostics[1].message.contains("'Clients'"))
        XCTAssertTrue(diagnostics[7].message.contains("Ventes[Total orphelin]"))
    }

    func testConflitAndJsonInvalideAreErrors() throws {
        XCTAssertEqual(Validator.validate(try Fixtures.load("Conflit")).filter { $0.severity == .error }.map(\.code),
                       ["report.conflictingFormats", "model.conflictingFormats"])
        XCTAssertEqual(Validator.validate(try Fixtures.load("JsonInvalide")).filter { $0.severity == .error }.map(\.code),
                       ["json.invalid"])
    }

    func testPublieHasNoErrorAndNoUnusedMeasureCheck() throws {
        let diagnostics = Validator.validate(try Fixtures.load("Publie"))
        XCTAssertEqual(diagnostics.map(\.code), ["report.modelNotLocal"])
    }

    func testBrokenHierarchyAndDAXReference() throws {
        var model = SemanticModel(format: .tmdl, tables: [
            Table(name: "T", columns: [Column(name: "A")],
                  measures: [Measure(name: "M", expression: "SUM(T[Absente]) + SUM(v[x])")],
                  hierarchies: [Hierarchy(name: "H", levels: [.init(name: "L", column: "Fantôme")])]),
        ])
        model.relationships = []
        let project = Project(name: "x", rootURL: URL(fileURLWithPath: "/tmp"), semanticModelPath: "x.SemanticModel", semanticModel: model)
        let diagnostics = Validator.validate(project)
        XCTAssertEqual(diagnostics.map(\.code), ["model.brokenHierarchy", "dax.unknownReference"],
                       "unknown table 'v' is ignored: it may be a table variable")
    }
}
