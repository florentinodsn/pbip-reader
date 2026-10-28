import XCTest

/// Lance l'exécutable `pbip` construit par `swift build`, pour vérifier les codes de sortie.
final class CLITests: XCTestCase {
    var executable: URL {
        // .build/<config>/PBIPKitTests.xctest/Contents/MacOS/… → .build/<config>/pbip
        var url = Bundle(for: CLITests.self).bundleURL
        while url.pathExtension != "xctest", url.path != "/" { url.deleteLastPathComponent() }
        return url.deletingLastPathComponent().appendingPathComponent("pbip")
    }

    func run(_ arguments: [String]) throws -> (status: Int32, output: String) {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("pbip executable not built at \(executable.path)")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testValidateExitCodes() throws {
        XCTAssertEqual(try run(["validate", Fixtures.url("Ventes").path, "--no-color"]).status, 0)
        XCTAssertEqual(try run(["validate", Fixtures.url("Publie").path, "--no-color"]).status, 0)
        XCTAssertEqual(try run(["validate", Fixtures.url("RefCassee").path, "--no-color"]).status, 1)
        XCTAssertEqual(try run(["validate", Fixtures.url("Conflit").path, "--no-color"]).status, 1)
    }

    func testValidateCanSkipUnusedMeasures() throws {
        let path = Fixtures.root.appendingPathComponent("Partage/Achats.pbip").path
        XCTAssertTrue(try run(["validate", path, "--no-color"]).output.contains("model.unusedMeasure"))
        let (status, output) = try run(["validate", path, "--no-color", "--no-unused-measures"])
        XCTAssertEqual(status, 0)
        XCTAssertFalse(output.contains("model.unusedMeasure"), output)
    }

    func testInfoOnTheThreeExamples() throws {
        for name in ["Ventes", "VentesLegacy", "Publie"] {
            let (status, output) = try run(["info", Fixtures.url(name).path, "--no-color"])
            XCTAssertEqual(status, 0, output)
            XCTAssertTrue(output.hasPrefix(name), output)
        }
    }

    func testUnknownPathFails() throws {
        let (status, output) = try run(["info", "/nonexistent/x.pbip"])
        XCTAssertEqual(status, 2)
        XCTAssertFalse(output.contains("Usage"), output)
        XCTAssertTrue(output.contains("No such file"), output)
    }

    func testLineageForAMissingNameFails() throws {
        XCTAssertEqual(try run(["lineage", Fixtures.url("Ventes").path, "--measure", "Nope"]).status, 2)
        XCTAssertEqual(try run(["model", Fixtures.url("Publie").path]).status, 2)
    }
}
