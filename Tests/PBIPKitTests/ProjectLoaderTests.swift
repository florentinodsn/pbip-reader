import XCTest
@testable import PBIPKit

final class ProjectLoaderTests: XCTestCase {
    func testVentesIsPBIRAndTMDL() throws {
        let project = try Fixtures.load("Ventes")
        XCTAssertEqual(project.name, "Ventes")
        XCTAssertEqual(project.report?.format, .pbir)
        XCTAssertEqual(project.semanticModel?.format, .tmdl)
        XCTAssertEqual(project.reportPath, "Ventes.Report")
        XCTAssertEqual(project.semanticModelPath, "Ventes.SemanticModel")
        XCTAssertEqual(project.datasetReference, DatasetReference(kind: .byPath, path: "../Ventes.SemanticModel"))
        XCTAssertEqual(project.reportDisplayName, "Ventes")
        XCTAssertFalse(project.diagnostics.hasErrors, "\(project.diagnostics)")
    }

    func testVentesLegacyIsLegacyAndBim() throws {
        let project = try Fixtures.load("VentesLegacy")
        XCTAssertEqual(project.report?.format, .legacy)
        XCTAssertEqual(project.semanticModel?.format, .bim)
        XCTAssertFalse(project.diagnostics.hasErrors, "\(project.diagnostics)")
    }

    func testPublieReadsReportOnly() throws {
        let project = try Fixtures.load("Publie")
        XCTAssertEqual(project.report?.format, .pbir)
        XCTAssertNil(project.semanticModel)
        XCTAssertEqual(project.datasetReference?.kind, .byConnection)
        XCTAssertEqual(project.datasetReference?.modelName, "Modèle Exemple")
        XCTAssertEqual(project.diagnostics(code: "report.modelNotLocal").count, 1)
        XCTAssertFalse(project.diagnostics.hasErrors)
    }

    func testConflictingFormatsAreErrors() throws {
        let project = try Fixtures.load("Conflit")
        XCTAssertEqual(project.diagnostics(code: "report.conflictingFormats").first?.file, "Conflit.Report")
        XCTAssertEqual(project.diagnostics(code: "model.conflictingFormats").first?.file, "Conflit.SemanticModel")
        // On lit quand même le format PBIR / TMDL pour afficher quelque chose.
        XCTAssertEqual(project.report?.format, .pbir)
        XCTAssertEqual(project.semanticModel?.format, .tmdl)
    }

    func testEntryPoints() throws {
        let folder = Fixtures.root.appendingPathComponent("Ventes")
        XCTAssertEqual(try ProjectLoader().load(folder).name, "Ventes")
        let report = try ProjectLoader().load(folder.appendingPathComponent("Ventes.Report"))
        XCTAssertEqual(report.semanticModel?.format, .tmdl, "a .Report folder follows byPath")
        let pbir = try ProjectLoader().load(folder.appendingPathComponent("Ventes.Report/definition.pbir"))
        XCTAssertEqual(pbir.report?.format, .pbir)
        let model = try ProjectLoader().load(folder.appendingPathComponent("Ventes.SemanticModel"))
        XCTAssertNil(model.report)
        XCTAssertEqual(model.semanticModel?.format, .tmdl)
    }

    func testMissingPathThrows() {
        XCTAssertThrowsError(try ProjectLoader().load(Fixtures.root.appendingPathComponent("Nope.pbip")))
        XCTAssertThrowsError(try ProjectLoader().load(Fixtures.root)) { error in
            XCTAssertEqual(error as? ProjectLoaderError, .notAProject(Fixtures.root.standardizedFileURL.path))
        }
    }

    func testConnectionStringModelName() {
        XCTAssertEqual(ProjectLoader.modelName(fromConnectionString:
            "Data Source=\"powerbi://x/y\";initial catalog=Mon Modèle;access mode=readonly"), "Mon Modèle")
        XCTAssertEqual(ProjectLoader.modelName(fromConnectionString: "semanticmodelid=1234"), "1234")
        XCTAssertNil(ProjectLoader.modelName(fromConnectionString: "Data Source=x"))
    }

    func testSchemaVersionParsing() {
        let parsed = SchemaVersion.parse("https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json")
        XCTAssertEqual(parsed, SchemaVersion.Parsed(name: "item/report/definition/page", major: 2, minor: 1, patch: 0))
        XCTAssertNil(SchemaVersion.parse("https://example.com/schema.json"))
    }
}
