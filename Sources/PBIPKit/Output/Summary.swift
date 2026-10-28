import Foundation

/// Résumé d'un projet, sortie de `pbip info`.
public struct ProjectSummary: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var pages = 0
        public var visuals = 0
        public var bookmarks = 0
        public var tables = 0
        public var columns = 0
        public var measures = 0
        public var relationships = 0
        public var expressions = 0
        public var roles = 0
    }

    public struct DiagnosticCounts: Codable, Equatable, Sendable {
        public var errors = 0
        public var warnings = 0
        public var infos = 0
    }

    public var name: String
    public var reportPath: String?
    public var reportFormat: Report.Format?
    public var semanticModelPath: String?
    public var semanticModelFormat: SemanticModel.Format?
    public var compatibilityLevel: Int?
    public var culture: String?
    public var datasetReference: DatasetReference?
    public var counts: Counts
    public var diagnostics: DiagnosticCounts

    public init(_ project: Project) {
        name = project.reportDisplayName ?? project.name
        reportPath = project.reportPath
        reportFormat = project.report?.format
        semanticModelPath = project.semanticModelPath
        semanticModelFormat = project.semanticModel?.format
        compatibilityLevel = project.semanticModel?.compatibilityLevel
        culture = project.semanticModel?.culture
        datasetReference = project.datasetReference

        var counts = Counts()
        if let report = project.report {
            counts.pages = report.pages.count
            counts.visuals = report.visualCount
            counts.bookmarks = report.bookmarks.count
        }
        if let model = project.semanticModel {
            counts.tables = model.tables.count
            counts.columns = model.tables.reduce(0) { $0 + $1.columns.count }
            counts.measures = model.measureCount
            counts.relationships = model.relationships.count
            counts.expressions = model.expressions.count
            counts.roles = model.roles.count
        }
        self.counts = counts

        var diagnostics = DiagnosticCounts()
        for d in project.diagnostics {
            switch d.severity {
            case .error: diagnostics.errors += 1
            case .warning: diagnostics.warnings += 1
            case .info: diagnostics.infos += 1
            }
        }
        self.diagnostics = diagnostics
    }
}
