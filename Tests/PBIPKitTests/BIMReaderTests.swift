import XCTest
@testable import PBIPKit

final class BIMReaderTests: XCTestCase {
    func build(_ json: String) throws -> (SemanticModel, [Diagnostic]) {
        let sink = DiagnosticSink(root: URL(fileURLWithPath: "/tmp"))
        let model = BIMModelBuilder(sink: sink, url: URL(fileURLWithPath: "/tmp/model.bim")).build(try JSON.parse(json))
        return (model, sink.items)
    }

    /// Critère de l'étape 5 : les deux formats donnent le même SemanticModel.
    func testVentesAndVentesLegacyProduceTheSameSemanticModel() throws {
        let tmdl = try XCTUnwrap(Fixtures.load("Ventes").semanticModel)
        var bim = try XCTUnwrap(Fixtures.load("VentesLegacy").semanticModel)
        XCTAssertEqual(tmdl.format, .tmdl)
        XCTAssertEqual(bim.format, .bim)
        bim.format = .tmdl

        // Comparaison détaillée d'abord, pour un message d'échec lisible.
        XCTAssertEqual(tmdl.tables.map(\.name), bim.tables.map(\.name))
        for (a, b) in zip(tmdl.tables, bim.tables) {
            XCTAssertEqual(a.columns, b.columns, a.name)
            XCTAssertEqual(a.measures, b.measures, a.name)
            XCTAssertEqual(a.partitions, b.partitions, a.name)
            XCTAssertEqual(a.hierarchies, b.hierarchies, a.name)
        }
        XCTAssertEqual(tmdl.relationships, bim.relationships)
        XCTAssertEqual(tmdl.expressions, bim.expressions)
        XCTAssertEqual(tmdl.roles, bim.roles)
        XCTAssertEqual(tmdl, bim)
    }

    func testExpressionAsArrayOfLines() throws {
        let (model, _) = try build("""
        {"model": {"tables": [{"name": "T", "measures": [
            {"name": "M", "expression": ["", "VAR x = 1", "RETURN", "    x", ""]}]}]}}
        """)
        XCTAssertEqual(model.tables[0].measures[0].expression, "VAR x = 1\nRETURN\n    x")
    }

    func testDefaultsAndUnknownPropertiesAreTolerated() throws {
        let (model, diagnostics) = try build("""
        {"compatibilityLevel": 1550, "somethingNew": {"a": 1},
         "model": {"culture": "en-US", "futureFeature": true,
          "tables": [{"name": "Sales", "columns": [
             {"type": "rowNumber", "name": "RowNumber-2662979B"},
             {"name": "Amount", "dataType": "Double", "sourceColumn": "amount"},
             {"type": "calculated", "name": "Twice", "expression": "[Amount] * 2"}],
             "partitions": [{"name": "Sales", "source": {"type": "entity", "entityName": "sales"}}]}],
          "relationships": [{"name": "r", "fromTable": "Sales", "fromColumn": "Amount", "toTable": "X", "toColumn": "Y",
                             "isActive": false, "unknown": 1}]}}
        """)
        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(model.compatibilityLevel, 1550)
        XCTAssertEqual(model.tables[0].columns.map(\.name), ["Amount", "Twice"], "rowNumber columns are skipped")
        XCTAssertEqual(model.tables[0].columns[0].dataType, "double")
        XCTAssertEqual(model.tables[0].columns[1].expression, "[Amount] * 2")
        XCTAssertEqual(model.tables[0].partitions[0], Partition(name: "Sales", sourceKind: "entity", expression: "sales"))
        XCTAssertEqual(model.relationships[0].isActive, false)
        XCTAssertEqual(model.relationships[0].cardinality, "many:one")
    }

    func testMissingModelObjectIsAnError() throws {
        let (_, diagnostics) = try build("{\"name\": \"x\"}")
        XCTAssertEqual(diagnostics.map(\.code), ["bim.noModel"])
    }
}
