import ArgumentParser
import Foundation
import PBIPKit

@main
struct Pbip: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pbip",
        abstract: "Read-only explorer for PBIP projects (report + semantic model).",
        version: PBIPKit.version,
        subcommands: [Info.self, Validate.self]
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
            throw ValidationError(error.description)
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

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Summary: formats, pages, visuals, tables, measures, relationships.")

    @OptionGroup var options: CommonOptions

    func run() throws {
        let project = try options.loadProject()
        write(InfoRenderer(style: options.style).render(project, format: options.outputFormat))
    }
}

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Diagnostics: broken references, unknown fields, conflicting formats, unused measures.")

    @OptionGroup var options: CommonOptions

    func run() throws {
        let project = try options.loadProject()
        let style = options.style
        for d in project.diagnostics.sortedForOutput() {
            let location = [d.file, d.line.map(String.init)].compactMap { $0 }.joined(separator: ":")
            write("\(style.severity(d.severity))  \(d.code)  \(location)  \(d.message)\n")
        }
        if project.diagnostics.hasErrors { throw ExitCode(1) }
    }
}
