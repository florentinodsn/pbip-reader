import ArgumentParser
import Foundation
import PBIPKit

@main
struct Pbip: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pbip",
        abstract: "Read-only explorer for PBIP projects (report + semantic model).",
        version: PBIPKitVersion.current,
        subcommands: [Info.self, Model.self, ReportCommand.self, LineageCommand.self, Validate.self]
    )
}

/// Options communes à toutes les commandes.
struct CommonOptions: ParsableArguments {
    @Argument(help: "A .pbip file, a folder containing one, a .Report folder or a .SemanticModel folder.")
    var path: String

    @Option(name: .long, help: "Output format: text, json or markdown.")
    var format: OutputFormatArgument = .text

    @Flag(name: .customLong("no-color"), help: "Disable ANSI colors in text output.")
    var noColor = false

    var outputFormat: OutputFormat { format.value }

    var style: Style {
        let isTTY = isatty(fileno(stdout)) != 0
        let noColorEnv = ProcessInfo.processInfo.environment["NO_COLOR"] != nil
        return Style(color: !noColor && !noColorEnv && isTTY && format.value == .text)
    }

    func loadProject() throws -> Project {
        do {
            return try ProjectLoader().load(URL(fileURLWithPath: path))
        } catch let error as ProjectLoaderError {
            throw fail(error.description)
        }
    }
}

struct OutputFormatArgument: ExpressibleByArgument {
    var value: OutputFormat

    init?(argument: String) {
        guard let value = OutputFormat(rawValue: argument.lowercased()) else { return nil }
        self.value = value
    }

    init(_ value: OutputFormat) {
        self.value = value
    }

    static var allValueStrings: [String] { OutputFormat.allCases.map(\.rawValue) }
    static let text = OutputFormatArgument(.text)
}

func write(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

/// Échec sans rappel de l'usage. Codes de sortie : 0 succès, 1 erreurs de validation, 2 lecture impossible.
func fail(_ message: String) -> ExitCode {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    return ExitCode(2)
}

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Summary: formats, pages, visuals, tables, measures, relationships.")

    @OptionGroup var options: CommonOptions

    func run() throws {
        let project = try options.loadProject()
        write(InfoRenderer(style: options.style).render(project, format: options.outputFormat))
    }
}

struct Model: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Tables, columns, measures (with DAX), relationships, M queries.")

    @OptionGroup var options: CommonOptions

    @Option(name: .long, help: "Only show this table and its relationships.")
    var table: String?

    func run() throws {
        let project = try options.loadProject()
        guard let model = project.semanticModel else {
            throw fail(project.datasetReference?.kind == .byConnection
                ? "The report uses a published semantic model; no local model to show."
                : "No readable semantic model in this project. Run 'pbip validate' for details.")
        }
        guard let filtered = ModelRenderer.filter(model, table: table) else {
            throw fail("No table named '\(table ?? "")'. Tables: \(model.tables.map(\.name).joined(separator: ", "))")
        }
        write(ModelRenderer(style: options.style).render(filtered, format: options.outputFormat))
    }
}

struct ReportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Pages and visuals, with the fields they use.")

    @OptionGroup var options: CommonOptions

    @Option(name: .long, help: "Only show this page (id or display name).")
    var page: String?

    func run() throws {
        let project = try options.loadProject()
        guard let report = project.report else {
            throw fail("No readable report in this project. Run 'pbip validate' for details.")
        }
        guard let filtered = ReportRenderer.filter(report, page: page) else {
            throw fail("No page named '\(page ?? "")'. Pages: \(report.pages.map(\.displayName).joined(separator: ", "))")
        }
        write(ReportRenderer(style: options.style).render(filtered, format: options.outputFormat))
    }
}

struct LineageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lineage",
        abstract: "For each measure or column, the visuals that use it; and the reverse.")

    @OptionGroup var options: CommonOptions

    @Option(name: .long, help: "Only show objects with this name (measure or column).")
    var measure: String?

    func run() throws {
        let project = try options.loadProject()
        let lineage = LineageBuilder.build(project)
        guard let filtered = LineageRenderer.filter(lineage, name: measure) else {
            throw fail("No measure or column named '\(measure ?? "")'.")
        }
        write(LineageRenderer(style: options.style).render(filtered, format: options.outputFormat))
    }
}

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Diagnostics: broken references, unknown fields, conflicting formats, unused measures. Exits with 1 on errors.")

    @OptionGroup var options: CommonOptions

    @Flag(name: .customLong("no-unused-measures"),
          help: "Do not report unused measures (for a model shared with reports published elsewhere).")
    var noUnusedMeasures = false

    func run() throws {
        let project = try options.loadProject()
        let diagnostics = Validator.validate(project, unusedMeasures: !noUnusedMeasures)
        write(ValidationRenderer(style: options.style).render(diagnostics, format: options.outputFormat))
        if diagnostics.hasErrors { throw ExitCode(1) }
    }
}
