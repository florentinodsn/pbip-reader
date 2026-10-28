import XCTest
@testable import PBIPKit

final class TMDLParserTests: XCTestCase {
    struct Reported: Equatable {
        var code: String
        var line: Int?
    }

    /// Analyse un texte TMDL écrit avec des tabulations.
    func parse(_ text: String) -> (nodes: [TMDLNode], reported: [Reported]) {
        var reported: [Reported] = []
        var parser = TMDLParser(text: text, file: "test.tmdl") { _, code, _, line in
            reported.append(Reported(code: code, line: line))
        }
        return (parser.parse(), reported)
    }

    func build(_ text: String) -> (SemanticModel, [Diagnostic]) {
        let sink = DiagnosticSink(root: URL(fileURLWithPath: "/tmp"))
        var parser = TMDLParser(text: text, file: "test.tmdl") { severity, code, message, line in
            sink.add(severity, code, message, line: line)
        }
        let model = TMDLModelBuilder(sink: sink, root: URL(fileURLWithPath: "/tmp")).build(parser.parse())
        return (model, sink.items)
    }

    // MARK: - Déclarations et noms

    func testObjectDeclarationWithNameAndChildren() {
        let (nodes, reported) = parse("table Sales\n\tlineageTag: abc\n\n\tcolumn Quantity\n\t\tdataType: int64\n")
        XCTAssertEqual(reported, [])
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].kind, "table")
        XCTAssertEqual(nodes[0].name, "Sales")
        XCTAssertEqual(nodes[0].property("lineageTag"), "abc")
        XCTAssertEqual(nodes[0].children.first?.name, "Quantity")
        XCTAssertEqual(nodes[0].children.first?.property("dataType"), "int64")
    }

    func testQuotedNamesWithEscapedApostrophe() {
        let (nodes, _) = parse("table 'L''année fiscale'\n\tmeasure 'Total (N-1)' = 1\n")
        XCTAssertEqual(nodes[0].name, "L'année fiscale")
        XCTAssertEqual(nodes[0].children[0].name, "Total (N-1)")
        XCTAssertEqual(nodes[0].children[0].defaultValue, "1")
    }

    func testUnquotedNameWithHyphenAndDefaultValue() {
        let (nodes, _) = parse("table Sales\n\tpartition Sales-Partition1 = m\n\t\tmode: import\n")
        let partition = nodes[0].children[0]
        XCTAssertEqual(partition.name, "Sales-Partition1")
        XCTAssertEqual(partition.defaultValue, "m")
        XCTAssertEqual(partition.property("mode"), "import")
    }

    func testKeywordsAreCaseInsensitive() {
        let (nodes, reported) = parse("TABLE Sales\n\tMeasure X = 1\n")
        XCTAssertEqual(reported, [])
        XCTAssertEqual(nodes[0].kind, "table")
        XCTAssertEqual(nodes[0].children("measure").count, 1)
    }

    // MARK: - Propriétés

    func testBooleanFlagAndExplicitBoolean() {
        let (nodes, _) = parse("table T\n\tcolumn C\n\t\tisHidden\n\t\tisAvailableInMdx: false\n")
        let column = nodes[0].children[0]
        XCTAssertEqual(column.flag("isHidden"), true)
        XCTAssertEqual(column.flag("isAvailableInMdx"), false)
        XCTAssertNil(column.flag("isKey"))
    }

    func testDoubleQuotedValueIsUnescaped() {
        let (nodes, _) = parse("table T\n\tmeasure M = 1\n\t\tdisplayFolder: \" My \"\"Amazing\"\" Measures\"\n")
        XCTAssertEqual(nodes[0].children[0].property("displayFolder"), " My \"Amazing\" Measures")
    }

    func testPropertyValueWithColonIsKeptWhole() {
        let (nodes, _) = parse("table T\n\tcolumn C\n\t\tformatString: hh:mm:ss\n")
        XCTAssertEqual(nodes[0].children[0].property("formatString"), "hh:mm:ss")
    }

    // MARK: - Expressions

    func testSingleLineExpression() {
        let (nodes, _) = parse("table T\n\tmeasure 'Sales Amount' = SUMX('Sales', [Qty] * [Price])\n\t\tformatString: $ #,##0\n")
        let m = nodes[0].children[0]
        XCTAssertEqual(m.defaultValue, "SUMX('Sales', [Qty] * [Price])")
        XCTAssertEqual(m.property("formatString"), "$ #,##0")
    }

    func testMultiLineExpressionStripsOuterIndentationAndKeepsInnerOne() {
        let text = "table T\n\tmeasure Q =\n\t\t\tvar r = SUMX(\n\t\t\t\tT, 1)\n\n\t\t\treturn r\n\t\tformatString: 0\n"
        let (nodes, reported) = parse(text)
        XCTAssertEqual(reported, [])
        let m = nodes[0].children[0]
        XCTAssertEqual(m.defaultValue, "var r = SUMX(\n\tT, 1)\n\nreturn r")
        XCTAssertEqual(m.property("formatString"), "0")
    }

    func testTrailingBlankLinesAreDropped() {
        let (nodes, _) = parse("table T\n\tmeasure Q =\n\t\t\t1 + 1\n\n\n\tcolumn C\n")
        XCTAssertEqual(nodes[0].children[0].defaultValue, "1 + 1")
        XCTAssertEqual(nodes[0].children[1].name, "C")
    }

    func testExpressionProperty() {
        let text = "table T\n\tpartition P = m\n\t\tmode: import\n\t\tsource =\n\t\t\t\tlet\n\t\t\t\t\tx = 1\n\t\t\t\tin\n\t\t\t\t\tx\n\n\tcolumn C\n"
        let (nodes, reported) = parse(text)
        XCTAssertEqual(reported, [])
        let p = nodes[0].children[0]
        XCTAssertEqual(p.property("source"), "let\n\tx = 1\nin\n\tx")
        XCTAssertEqual(p.properties.first { $0.name == "source" }?.isExpression, true)
        XCTAssertEqual(nodes[0].children.count, 2)
    }

    func testExpressionPropertyOneLevelDeeperAsInTheDocs() {
        let text = "table T\n\tpartition P = m\n\t\tsource =\n\t\t\tlet\n\t\t\t\tx = 1\n\t\t\tin\n\t\t\t\tx\n"
        XCTAssertEqual(parse(text).nodes[0].children[0].property("source"), "let\n\tx = 1\nin\n\tx")
    }

    func testBacktickExpressionIsVerbatimWithClosingMargin() {
        let text = "table T\n\tmeasure M = ```\n\t\t\t\tvar x = 1\n\t\t\t  \n\t\t\treturn x\n\t\t\t```\n\t\tformatString: 0\n"
        let (nodes, reported) = parse(text)
        XCTAssertEqual(reported, [])
        // Marge = indentation de la ligne de fermeture (3 tabulations) ; le reste est conservé.
        XCTAssertEqual(nodes[0].children[0].defaultValue, "\tvar x = 1\n  \nreturn x")
        XCTAssertEqual(nodes[0].children[0].property("formatString"), "0")
    }

    func testUnclosedBackticksIsReported() {
        let (_, reported) = parse("table T\n\tmeasure M = ```\n\t\t\t1\n")
        XCTAssertEqual(reported.map(\.code), ["tmdl.unclosedBackticks"])
    }

    func testExpressionFollowedByMetaOnOneLine() {
        let (nodes, _) = parse("expression Server = \"localhost\" meta [IsParameterQuery=true, Type=\"Text\"]\n\tlineageTag: x\n")
        XCTAssertEqual(nodes[0].defaultValue, "\"localhost\" meta [IsParameterQuery=true, Type=\"Text\"]")
        XCTAssertEqual(nodes[0].property("lineageTag"), "x")
    }

    // MARK: - Descriptions, ref, fins de ligne, espaces

    func testDescriptionsOnOneOrSeveralLines() {
        let (nodes, _) = parse("/// Table Description\ntable Sales\n\n\t/// Line one\n\t/// Line two\n\tmeasure M = 1\n")
        XCTAssertEqual(nodes[0].description, "Table Description")
        XCTAssertEqual(nodes[0].children[0].description, "Line one\nLine two")
    }

    func testDescriptionSeparatedByBlankLineIsDetached() {
        let (nodes, reported) = parse("/// Lost\n\ntable Sales\n")
        XCTAssertNil(nodes[0].description)
        XCTAssertEqual(reported.map(\.code), ["tmdl.detachedDescription"])
    }

    func testRefNodes() {
        let (nodes, _) = parse("model Model\n\tculture: fr-FR\n\nref table Calendar\nref table 'Sales Lines'\nref cultureInfo fr-FR\n")
        let refs = nodes.filter(\.isRef)
        XCTAssertEqual(refs.map(\.kind), ["table", "table", "cultureinfo"])
        XCTAssertEqual(refs.map(\.name), ["Calendar", "Sales Lines", "fr-FR"])
    }

    func testCRLFAndLFGiveTheSameTree() {
        let lf = "table T\n\tmeasure Q =\n\t\t\tvar r = 1\n\t\t\treturn r\n\t\tformatString: 0\n"
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(parse(lf).nodes.map(\.children), parse(crlf).nodes.map(\.children))
        XCTAssertEqual(parse(crlf).nodes[0].children[0].defaultValue, "var r = 1\nreturn r")
    }

    func testSpaceIndentationIsAccepted() {
        let text = "table T\n    measure Q =\n            1 +\n                2\n        formatString: 0\n"
        let (nodes, reported) = parse(text)
        XCTAssertEqual(reported, [])
        XCTAssertEqual(nodes[0].children[0].defaultValue, "1 +\n    2")
        XCTAssertEqual(nodes[0].children[0].property("formatString"), "0")
    }

    func testMixedIndentationIsWarned() {
        let (_, reported) = parse("table T\n\tcolumn A\n    column B\n")
        XCTAssertTrue(reported.map(\.code).contains("tmdl.mixedIndentation"))
    }

    // MARK: - Tolérance

    func testUnknownKeywordIsKeptAsGenericNode() {
        let (nodes, reported) = parse("table T\n\tgadget Thing = 42\n\t\tcolor: blue\n\tcolumn C\n")
        XCTAssertEqual(reported, [Reported(code: "tmdl.unknownKeyword", line: 2)])
        let gadget = nodes[0].children[0]
        XCTAssertTrue(gadget.isUnknown)
        XCTAssertEqual(gadget.name, "Thing")
        XCTAssertEqual(gadget.defaultValue, "42")
        XCTAssertEqual(gadget.property("color"), "blue")
        XCTAssertEqual(nodes[0].children[1].name, "C")
    }

    func testUnexpectedIndentationIsReportedNotFatal() {
        let (nodes, reported) = parse("table T\n\t\t\tcolumn Lost\n\tcolumn C\n")
        XCTAssertEqual(reported.map(\.code), ["tmdl.unexpectedIndentation"])
        XCTAssertEqual(nodes[0].children.map(\.name), ["C"])
    }

    func testCustomJSONObjectWithoutName() {
        let (nodes, reported) = parse("model Model\n\tdataAccessOptions\n\t\tlegacyRedirects\n\t\treturnErrorValuesAsNull\n")
        XCTAssertEqual(reported, [])
        let options = nodes[0].children[0]
        XCTAssertEqual(options.kind, "dataaccessoptions")
        XCTAssertNil(options.name)
        XCTAssertEqual(options.flag("legacyRedirects"), true)
    }

    // MARK: - Noms qualifiés

    func testQualifiedNames() {
        XCTAssertEqual(TMDLName.splitQualified("Sales.'Product Key'"), ["Sales", "Product Key"])
        XCTAssertEqual(TMDLName.splitQualified("'Table 1'.'Column 1'"), ["Table 1", "Column 1"])
        XCTAssertEqual(TMDLName.splitQualified("'A.B'.C"), ["A.B", "C"])
        XCTAssertEqual(TMDLName.splitQualified("'L''an'.Date"), ["L'an", "Date"])
    }

    // MARK: - Conversion vers SemanticModel

    func testBuilderDefaultsAndRelationships() {
        let text = """
        relationship r1
        \tfromColumn: Sales.'Product Key'
        \ttoColumn: Product.'Product Key'

        relationship r2
        \tisActive: false
        \tcrossFilteringBehavior: BothDirections
        \ttoCardinality: many
        \tfromColumn: 'Sales'.Date
        \ttoColumn: Calendar.Date

        """
        let (model, diagnostics) = build(text)
        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(model.relationships[0], Relationship(
            id: "r1", from: ColumnRef(table: "Sales", column: "Product Key"),
            to: ColumnRef(table: "Product", column: "Product Key")))
        XCTAssertEqual(model.relationships[1].isActive, false)
        XCTAssertEqual(model.relationships[1].crossFilteringBehavior, "bothDirections")
        XCTAssertEqual(model.relationships[1].cardinality, "many:many")
    }

    func testPartialDeclarationsAreMerged() {
        let text = "table Sales\n\tcolumn A\n\ntable Product\n\ntable Sales\n\tmeasure M = 1\n"
        let (model, _) = build(text)
        XCTAssertEqual(model.tables.map(\.name), ["Sales", "Product"])
        XCTAssertEqual(model.tables[0].columns.map(\.name), ["A"])
        XCTAssertEqual(model.tables[0].measures.map(\.name), ["M"])
    }

    func testDuplicateMeasureIsAnError() {
        let (model, diagnostics) = build("table Sales\n\tmeasure M = 1\n\ntable Sales\n\tmeasure M = 2\n")
        XCTAssertEqual(model.tables[0].measures.count, 1)
        XCTAssertEqual(diagnostics.map(\.code), ["tmdl.duplicateObject"])
    }

    func testRefOrderWinsAndMissingRefIsInfo() {
        let text = "model Model\n\nref table B\nref table Ghost\nref table A\n\ntable A\n\ntable C\n\ntable B\n"
        let (model, diagnostics) = build(text)
        XCTAssertEqual(model.tables.map(\.name), ["B", "A", "C"])
        XCTAssertEqual(diagnostics.map(\.code), ["tmdl.refWithoutObject"])
        XCTAssertEqual(diagnostics.first?.severity, .info)
    }

    func testCalculatedColumnHierarchyAndCalculationGroup() {
        let text = """
        table Time
        \tcalculationGroup
        \t\tcalculationItem YTD = CALCULATE(SELECTEDMEASURE(), DATESYTD('Date'[Date]))

        \tcolumn Amount = [Qty] * [Price]
        \t\tdataType: Decimal

        \thierarchy Geo
        \t\tlevel Country
        \t\t\tcolumn: 'Country Name'

        """
        let (model, diagnostics) = build(text)
        XCTAssertEqual(diagnostics, [])
        let table = model.tables[0]
        XCTAssertEqual(table.calculationItems, [CalculationItem(name: "YTD", expression: "CALCULATE(SELECTEDMEASURE(), DATESYTD('Date'[Date]))")])
        XCTAssertEqual(table.columns[0].expression, "[Qty] * [Price]")
        XCTAssertEqual(table.columns[0].dataType, "decimal")
        XCTAssertEqual(table.hierarchies[0].levels, [Hierarchy.Level(name: "Country", column: "Country Name")])
    }

    func testParameterExpressionIsDetected() {
        let (model, _) = build("expression P = \"x\" meta [IsParameterQuery = true, Type=\"Text\"]\n\nexpression Q =\n\t\tlet a = 1 in a\n")
        XCTAssertEqual(model.expressions.map(\.isParameter), [true, false])
        XCTAssertEqual(model.expressions[1].expression, "let a = 1 in a")
    }

    // MARK: - Fichier d'exemple complet

    func testVentesFixtureModel() throws {
        let project = try Fixtures.load("Ventes")
        XCTAssertEqual(project.diagnostics, [])
        let model = try XCTUnwrap(project.semanticModel)
        XCTAssertEqual(model.compatibilityLevel, 1702)
        XCTAssertEqual(model.culture, "fr-FR")
        XCTAssertEqual(model.tables.map(\.name), ["Ventes", "Produits", "Calendrier"])
        XCTAssertEqual(model.measureCount, 5)
        XCTAssertEqual(model.relationships.count, 2)
        XCTAssertEqual(model.cultures, ["fr-FR"])
        XCTAssertEqual(model.roles.first?.name, "Lecteurs France")

        let ventes = try XCTUnwrap(model.table(named: "Ventes"))
        XCTAssertEqual(ventes.description, "Lignes de vente fictives.")
        XCTAssertEqual(ventes.column(named: "Prix unitaire")?.formatString, "0.00 \"€\"")
        XCTAssertEqual(ventes.column(named: "Montant HT")?.expression, "Ventes[Quantité] * Ventes[Prix unitaire]")
        XCTAssertEqual(ventes.column(named: "Montant HT")?.isHidden, true)
        XCTAssertEqual(ventes.measure(named: "Panier moyen")?.expression,
                       "VAR nb = DISTINCTCOUNT(Ventes[Date])\nRETURN\n\tDIVIDE([Total HT], nb)")
        XCTAssertEqual(ventes.measure(named: "Total HT N-1")?.expression,
                       "CALCULATE(\n\t[Total HT],\n\tSAMEPERIODLASTYEAR('Calendrier'[Date])\n)")
        XCTAssertEqual(ventes.measure(named: "Marge %")?.description,
                       "Marge estimée, coût fictif à 60 % du prix.\nSert d'exemple de description sur deux lignes.")
        XCTAssertEqual(ventes.partitions.first?.sourceKind, "m")
        XCTAssertEqual(ventes.partitions.first?.expression?.components(separatedBy: "\n").first, "let")
        XCTAssertEqual(model.table(named: "Calendrier")?.partitions.first?.sourceKind, "calculated")
        XCTAssertEqual(model.expressions.first?.isParameter, true)

        XCTAssertEqual(model.functions, [
            UserFunction(name: "Fiscalite.AppliquerTVA",
                         expression: "(montant : NUMERIC, taux : NUMERIC = 0.2) =>\n\tmontant * ( 1 + taux )",
                         description: "Applique un taux de TVA (20 % par défaut) à un montant hors taxes."),
            UserFunction(name: "MontantTTC",
                         expression: "(montantHT : SCALAR NUMERIC VAL) =>\n\tROUND ( Fiscalite.AppliquerTVA ( montantHT ), 2 )"),
        ])
        XCTAssertEqual(model.callers(of: "fiscalite.appliquertva"), ["MontantTTC()"])
        XCTAssertEqual(model.callers(of: "MontantTTC"), [])
    }

    func testFunctionAsInTheDocsTMDLView() {
        // Forme de la doc « TMDL view » : description `///`, expression sur les lignes suivantes.
        let (model, diagnostics) = build("/// AddTax takes in amount and returns amount including tax\nfunction AddTax = \n\t\t(amount : NUMERIC) =>\n\t\t\tamount * 1.1\n")
        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(model.functions, [UserFunction(name: "AddTax", expression: "(amount : NUMERIC) =>\n\tamount * 1.1",
                                                      description: "AddTax takes in amount and returns amount including tax")])
    }

    func testRefCasseeFixtureReportsUnknownKeywordAndMissingRef() throws {
        let project = try Fixtures.load("RefCassee")
        let unknown = project.diagnostics(code: "tmdl.unknownKeyword")
        XCTAssertEqual(unknown.first?.file, "RefCassee.SemanticModel/definition/tables/Ventes.tmdl")
        XCTAssertEqual(unknown.first?.line, 15)
        XCTAssertEqual(project.diagnostics(code: "tmdl.refWithoutObject").count, 1)
    }
}
