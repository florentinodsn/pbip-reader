import XCTest
@testable import PBIPKit

final class SyntaxTokenizerTests: XCTestCase {
    func kinds(_ text: String, _ language: SyntaxTokenizer.Language) -> [String] {
        SyntaxTokenizer.tokenize(text, language: language)
            .filter { $0.kind != .plain }
            .map { "\($0.kind.rawValue):\($0.text)" }
    }

    func testDAX() {
        XCTAssertEqual(kinds("VAR x = SUM('Ventes'[Montant]) // note\nRETURN x * 1.5 & \"a\"\"b\"", .dax), [
            "keyword:VAR", "table:x", "function:SUM", "table:'Ventes'", "reference:[Montant]", "comment:// note",
            "keyword:RETURN", "table:x", "number:1.5", "string:\"a\"\"b\"",
        ])
    }

    func testM() {
        XCTAssertEqual(kinds("let\n\tSource = Csv.Document(#\"Dossier source\") /* c */\nin\n\tSource", .m), [
            "keyword:let", "function:Csv.Document", "reference:#\"Dossier source\"", "comment:/* c */", "keyword:in",
        ])
    }

    func testRoundTrip() throws {
        let model = try XCTUnwrap(Fixtures.load("Ventes").semanticModel)
        for table in model.tables {
            for m in table.measures {
                XCTAssertEqual(SyntaxTokenizer.tokenize(m.expression, language: .dax).map(\.text).joined(), m.expression)
            }
            for p in table.partitions {
                let e = p.expression ?? ""
                XCTAssertEqual(SyntaxTokenizer.tokenize(e, language: .m).map(\.text).joined(), e)
            }
        }
        XCTAssertEqual(SyntaxTokenizer.tokenize("\"non fermé", language: .dax).map(\.text).joined(), "\"non fermé")
    }
}
