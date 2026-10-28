import XCTest
@testable import PBIPKit

final class ModelDiagramTests: XCTestCase {
    /// Flocon : Ventes → Produits → Catégories, Ventes → Calendrier ; Notes sans relation.
    func snowflake() -> SemanticModel {
        SemanticModel(format: .tmdl, tables: [
            Table(name: "Ventes", columns: [Column(name: "Code Produit"), Column(name: "Date")]),
            Table(name: "Produits", columns: [Column(name: "Code Produit"), Column(name: "Code Catégorie")]),
            Table(name: "Catégories", columns: [Column(name: "Code Catégorie")]),
            Table(name: "Calendrier", columns: [Column(name: "Date")]),
            Table(name: "Notes", measures: [Measure(name: "Info", expression: "1")]),
        ], relationships: [
            Relationship(id: "1", from: ColumnRef(table: "Ventes", column: "Code Produit"), to: ColumnRef(table: "Produits", column: "Code Produit")),
            Relationship(id: "2", from: ColumnRef(table: "ventes", column: "Date"), to: ColumnRef(table: "Calendrier", column: "Date")),
            Relationship(id: "3", from: ColumnRef(table: "Produits", column: "Code Catégorie"), to: ColumnRef(table: "Catégories", column: "Code Catégorie")),
        ])
    }

    func testRoles() {
        XCTAssertEqual(ModelDiagram.roles(snowflake()), [
            "Ventes": .fact, "Produits": .dimension, "Catégories": .dimension, "Calendrier": .dimension, "Notes": .isolated,
        ])
        let ventes = ModelDiagram.roles(try! Fixtures.load("Ventes").semanticModel!)
        XCTAssertEqual(ventes["Ventes"], .fact)
        XCTAssertEqual(ventes["Produits"], .dimension)
        XCTAssertEqual(ventes["Calendrier"], .dimension)
    }

    func testGridPutsFactsOnTopAndDimensionsOnTheLeft() throws {
        let d = ModelDiagram.make(snowflake(), layout: .grid)
        XCTAssertEqual(d.nodes.count, 5)
        let fact = try XCTUnwrap(d.node("Ventes"))
        let dims = ["Produits", "Catégories", "Calendrier"].compactMap { d.node($0) }
        for dim in dims {
            XCTAssertLessThan(dim.x + dim.width, fact.x + 1, "\(dim.table) à gauche du fait")
            XCTAssertGreaterThan(dim.y, fact.y + fact.height - 1, "\(dim.table) sous la rangée des faits")
        }
        XCTAssertNoOverlap(d)
    }

    func testStarSurroundsFactAndPushesSnowflakeOutward() throws {
        let d = ModelDiagram.make(snowflake(), layout: .star)
        XCTAssertEqual(d.nodes.count, 5)
        let fact = try XCTUnwrap(d.node("Ventes"))
        func distance(_ name: String) throws -> Double {
            let n = try XCTUnwrap(d.node(name))
            return hypot(n.centerX - fact.centerX, n.centerY - fact.centerY)
        }
        XCTAssertGreaterThan(try distance("Catégories"), try distance("Produits"))
        // La table isolée est sous la grappe.
        let notes = try XCTUnwrap(d.node("Notes"))
        XCTAssertGreaterThan(notes.y, d.nodes.filter { $0.table != "Notes" }.map { $0.y + $0.height }.max()!)
        XCTAssertNoOverlap(d)
    }

    func testGridEdgesStartAndEndOnTheirBoxesAndCrossNoOtherBox() throws {
        // Deux dimensions empilées sous Ventes : la seconde ne doit pas traverser la première.
        let model = snowflake()
        let d = ModelDiagram.make(model, layout: .grid)
        XCTAssertEqual(d.edges.map(\.relationship), [0, 1, 2])
        for edge in d.edges {
            let r = model.relationships[edge.relationship]
            let from = try XCTUnwrap(d.node(r.from.table)), to = try XCTUnwrap(d.node(r.to.table))
            XCTAssertTrue(onBorder(edge.points.first!, from), "\(r.from.table) : départ sur le bord")
            XCTAssertTrue(onBorder(edge.points.last!, to), "\(r.to.table) : arrivée sur le bord")
            for n in d.nodes {
                for (a, b) in zip(edge.points, edge.points.dropFirst()) {
                    XCTAssertFalse(crossesInterior(a, b, n), "lien \(r.from.table) → \(r.to.table) traverse \(n.table)")
                }
            }
        }
        // Les liens vers le fait remontent à angle droit dans sa face inférieure.
        let calendrier = try XCTUnwrap(d.edges.first { $0.relationship == 1 })
        let ventes = try XCTUnwrap(d.node("Ventes"))
        XCTAssertEqual(calendrier.points.count, 5)
        XCTAssertEqual(calendrier.points.first!.y, ventes.y + ventes.height)
    }

    func onBorder(_ p: ModelDiagram.Point, _ n: ModelDiagram.Node) -> Bool {
        let inX = p.x >= n.x - 0.01 && p.x <= n.x + n.width + 0.01
        let inY = p.y >= n.y - 0.01 && p.y <= n.y + n.height + 0.01
        let edgeX = abs(p.x - n.x) < 0.01 || abs(p.x - n.x - n.width) < 0.01
        let edgeY = abs(p.y - n.y) < 0.01 || abs(p.y - n.y - n.height) < 0.01
        return inX && inY && (edgeX || edgeY)
    }

    /// Le segment passe-t-il à l'intérieur strict de la boîte ? (échantillonnage suffisant ici)
    func crossesInterior(_ a: ModelDiagram.Point, _ b: ModelDiagram.Point, _ n: ModelDiagram.Node) -> Bool {
        (0...200).contains { i in
            let t = Double(i) / 200
            let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
            return x > n.x + 1 && x < n.x + n.width - 1 && y > n.y + 1 && y < n.y + n.height - 1
        }
    }

    func testAutoDateTablesAreRemovedWithTheirRelationships() {
        var model = snowflake()
        let guid = "0a1b2c3d-0000-4000-8000-000000000001"
        model.tables += [
            Table(name: "LocalDateTable_\(guid)", isHidden: true, columns: [Column(name: "Date")]),
            Table(name: "DateTableTemplate_\(guid)", isHidden: true, columns: [Column(name: "Date")]),
        ]
        model.relationships.append(Relationship(id: "4", from: ColumnRef(table: "Ventes", column: "Date"),
                                                to: ColumnRef(table: "localdatetable_\(guid)", column: "Date")))
        let visible = model.withoutAutoDateTables
        XCTAssertEqual(visible.tables.map(\.name), snowflake().tables.map(\.name))
        XCTAssertEqual(visible.relationships, snowflake().relationships)
        XCTAssertEqual(snowflake().withoutAutoDateTables, snowflake())
    }

    func testBoxKeepsRelationshipColumnsWhenTruncated() {
        let columns = (1...20).map { Column(name: "C\($0)") }
        let model = SemanticModel(format: .tmdl, tables: [
            Table(name: "F", columns: columns + [Column(name: "Clé")]),
            Table(name: "D", columns: [Column(name: "Clé")]),
        ], relationships: [
            Relationship(id: "1", from: ColumnRef(table: "F", column: "clé"), to: ColumnRef(table: "D", column: "Clé")),
        ])
        let f = ModelDiagram.make(model, layout: .grid).node("F")!
        XCTAssertEqual(f.rows.count, ModelDiagram.maxRows)
        XCTAssertEqual(f.rows.last, "Clé")
        XCTAssertEqual(f.hiddenRowCount, 21 - ModelDiagram.maxRows)
    }

    func XCTAssertNoOverlap(_ d: ModelDiagram, file: StaticString = #filePath, line: UInt = #line) {
        for (i, a) in d.nodes.enumerated() {
            XCTAssertGreaterThanOrEqual(a.x, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(a.y, 0, file: file, line: line)
            for b in d.nodes[(i + 1)...] {
                let overlap = a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
                XCTAssertFalse(overlap, "\(a.table) chevauche \(b.table)", file: file, line: line)
            }
        }
    }

    // MARK: - Dossiers d'affichage

    func testMeasureFolders() {
        let tree = MeasureFolder.tree([
            Measure(name: "Total", expression: "1"),
            Measure(name: "Marge", expression: "1", displayFolder: "Indicateurs\\Rentabilité"),
            Measure(name: "CA", expression: "1", displayFolder: "indicateurs"),
            Measure(name: "Double", expression: "1", displayFolder: "A;Indicateurs"),
            Measure(name: "Vide", expression: "1", displayFolder: " \\ "),
        ])
        XCTAssertEqual(tree.measures, ["Total", "Vide"])
        XCTAssertEqual(tree.folders.map(\.name), ["A", "Indicateurs"])
        let indicateurs = tree.folders[1]
        XCTAssertEqual(indicateurs.measures, ["CA", "Double"])
        XCTAssertEqual(indicateurs.folders.map(\.path), ["Indicateurs\\Rentabilité"])
        XCTAssertEqual(indicateurs.folders[0].measures, ["Marge"])
        XCTAssertEqual(tree.measureCount, 6)
    }
}
