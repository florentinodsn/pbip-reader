import Foundation

/// Référence du rapport vers son modèle sémantique (`definition.pbir` → `datasetReference`).
public struct DatasetReference: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case byPath, byConnection
    }

    public var kind: Kind
    /// `byPath` : chemin relatif tel qu'écrit dans le fichier.
    public var path: String?
    /// `byConnection` : nom du modèle publié, extrait de la chaîne de connexion.
    public var modelName: String?
    public var connectionString: String?

    public init(kind: Kind, path: String? = nil, modelName: String? = nil, connectionString: String? = nil) {
        self.kind = kind
        self.path = path
        self.modelName = modelName
        self.connectionString = connectionString
    }
}

public struct Project: Codable, Equatable, Sendable {
    public var name: String
    /// Dossier racine du projet ; non sérialisé pour que la sortie ne dépende pas de la machine.
    public var rootURL: URL
    /// Chemins relatifs à `rootURL`.
    public var reportPath: String?
    public var semanticModelPath: String?
    /// Noms affichés lus dans `.platform`, s'ils existent.
    public var reportDisplayName: String?
    public var semanticModelDisplayName: String?
    public var report: Report?
    public var semanticModel: SemanticModel?
    public var datasetReference: DatasetReference?
    public var diagnostics: [Diagnostic]

    enum CodingKeys: String, CodingKey {
        case name, reportPath, semanticModelPath, reportDisplayName, semanticModelDisplayName
        case report, semanticModel, datasetReference, diagnostics
    }

    public init(name: String, rootURL: URL, reportPath: String? = nil, semanticModelPath: String? = nil,
                reportDisplayName: String? = nil, semanticModelDisplayName: String? = nil, report: Report? = nil,
                semanticModel: SemanticModel? = nil, datasetReference: DatasetReference? = nil,
                diagnostics: [Diagnostic] = []) {
        self.name = name
        self.rootURL = rootURL
        self.reportPath = reportPath
        self.semanticModelPath = semanticModelPath
        self.reportDisplayName = reportDisplayName
        self.semanticModelDisplayName = semanticModelDisplayName
        self.report = report
        self.semanticModel = semanticModel
        self.datasetReference = datasetReference
        self.diagnostics = diagnostics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        rootURL = URL(fileURLWithPath: ".")
        reportPath = try c.decodeIfPresent(String.self, forKey: .reportPath)
        semanticModelPath = try c.decodeIfPresent(String.self, forKey: .semanticModelPath)
        reportDisplayName = try c.decodeIfPresent(String.self, forKey: .reportDisplayName)
        semanticModelDisplayName = try c.decodeIfPresent(String.self, forKey: .semanticModelDisplayName)
        report = try c.decodeIfPresent(Report.self, forKey: .report)
        semanticModel = try c.decodeIfPresent(SemanticModel.self, forKey: .semanticModel)
        datasetReference = try c.decodeIfPresent(DatasetReference.self, forKey: .datasetReference)
        diagnostics = try c.decodeIfPresent([Diagnostic].self, forKey: .diagnostics) ?? []
    }
}
