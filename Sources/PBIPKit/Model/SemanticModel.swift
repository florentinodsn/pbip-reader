import Foundation

/// Modèle sémantique, identique quel que soit le format source (TMDL ou model.bim).
public struct SemanticModel: Codable, Equatable, Sendable {
    public enum Format: String, Codable, Sendable {
        case tmdl, bim
    }

    public var format: Format
    public var compatibilityLevel: Int?
    public var culture: String?
    public var tables: [Table]
    public var relationships: [Relationship]
    public var expressions: [NamedExpression]
    public var roles: [Role]
    public var cultures: [String]
    public var perspectives: [String]

    public init(format: Format, compatibilityLevel: Int? = nil, culture: String? = nil, tables: [Table] = [],
                relationships: [Relationship] = [], expressions: [NamedExpression] = [], roles: [Role] = [],
                cultures: [String] = [], perspectives: [String] = []) {
        self.format = format
        self.compatibilityLevel = compatibilityLevel
        self.culture = culture
        self.tables = tables
        self.relationships = relationships
        self.expressions = expressions
        self.roles = roles
        self.cultures = cultures
        self.perspectives = perspectives
    }

    public var measureCount: Int { tables.reduce(0) { $0 + $1.measures.count } }

    /// Les noms d'objets sont insensibles à la casse dans le moteur : on cherche de même.
    public func table(named name: String) -> Table? {
        tables.first { $0.name == name } ?? tables.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

public struct Table: Codable, Equatable, Sendable {
    public var name: String
    public var description: String?
    public var isHidden: Bool
    public var columns: [Column]
    public var measures: [Measure]
    public var partitions: [Partition]
    public var hierarchies: [Hierarchy]
    /// Non vide seulement pour un groupe de calcul.
    public var calculationItems: [CalculationItem]

    public init(name: String, description: String? = nil, isHidden: Bool = false, columns: [Column] = [],
                measures: [Measure] = [], partitions: [Partition] = [], hierarchies: [Hierarchy] = [],
                calculationItems: [CalculationItem] = []) {
        self.name = name
        self.description = description
        self.isHidden = isHidden
        self.columns = columns
        self.measures = measures
        self.partitions = partitions
        self.hierarchies = hierarchies
        self.calculationItems = calculationItems
    }

    public func column(named name: String) -> Column? {
        columns.first { $0.name == name } ?? columns.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func measure(named name: String) -> Measure? {
        measures.first { $0.name == name } ?? measures.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func hierarchy(named name: String) -> Hierarchy? {
        hierarchies.first { $0.name == name } ?? hierarchies.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

public struct Column: Codable, Equatable, Sendable {
    public var name: String
    public var dataType: String?
    public var sourceColumn: String?
    /// Expression DAX d'une colonne calculée.
    public var expression: String?
    public var formatString: String?
    public var displayFolder: String?
    public var description: String?
    public var isHidden: Bool

    public init(name: String, dataType: String? = nil, sourceColumn: String? = nil, expression: String? = nil,
                formatString: String? = nil, displayFolder: String? = nil, description: String? = nil,
                isHidden: Bool = false) {
        self.name = name
        self.dataType = dataType
        self.sourceColumn = sourceColumn
        self.expression = expression
        self.formatString = formatString
        self.displayFolder = displayFolder
        self.description = description
        self.isHidden = isHidden
    }

    public var isCalculated: Bool { expression != nil }
}

public struct Measure: Codable, Equatable, Sendable {
    public var name: String
    public var expression: String
    public var formatString: String?
    public var displayFolder: String?
    public var description: String?
    public var isHidden: Bool

    public init(name: String, expression: String, formatString: String? = nil, displayFolder: String? = nil,
                description: String? = nil, isHidden: Bool = false) {
        self.name = name
        self.expression = expression
        self.formatString = formatString
        self.displayFolder = displayFolder
        self.description = description
        self.isHidden = isHidden
    }
}

public struct Partition: Codable, Equatable, Sendable {
    public var name: String
    /// `import`, `directQuery`, `dual`, `directLake`… ; absent si non précisé.
    public var mode: String?
    /// `m`, `calculated`, `entity`, `query`, `policyRange`…
    public var sourceKind: String
    public var expression: String?

    public init(name: String, mode: String? = nil, sourceKind: String, expression: String? = nil) {
        self.name = name
        self.mode = mode
        self.sourceKind = sourceKind
        self.expression = expression
    }
}

public struct Hierarchy: Codable, Equatable, Sendable {
    public struct Level: Codable, Equatable, Sendable {
        public var name: String
        public var column: String

        public init(name: String, column: String) {
            self.name = name
            self.column = column
        }
    }

    public var name: String
    public var levels: [Level]

    public init(name: String, levels: [Level] = []) {
        self.name = name
        self.levels = levels
    }
}

public struct CalculationItem: Codable, Equatable, Sendable {
    public var name: String
    public var expression: String

    public init(name: String, expression: String) {
        self.name = name
        self.expression = expression
    }
}

public struct ColumnRef: Codable, Hashable, Sendable {
    public var table: String
    public var column: String

    public init(table: String, column: String) {
        self.table = table
        self.column = column
    }

    public var displayName: String { "\(table)[\(column)]" }
}

public struct Relationship: Codable, Equatable, Sendable {
    public var id: String
    public var from: ColumnRef
    public var to: ColumnRef
    public var fromCardinality: String
    public var toCardinality: String
    public var crossFilteringBehavior: String
    public var isActive: Bool

    public init(id: String, from: ColumnRef, to: ColumnRef, fromCardinality: String = "many",
                toCardinality: String = "one", crossFilteringBehavior: String = "oneDirection", isActive: Bool = true) {
        self.id = id
        self.from = from
        self.to = to
        self.fromCardinality = fromCardinality
        self.toCardinality = toCardinality
        self.crossFilteringBehavior = crossFilteringBehavior
        self.isActive = isActive
    }

    /// `many:one`, `one:one`…
    public var cardinality: String { "\(fromCardinality):\(toCardinality)" }
}

/// Expression partagée du modèle (requête M ou paramètre).
public struct NamedExpression: Codable, Equatable, Sendable {
    public var name: String
    public var kind: String
    public var expression: String
    public var isParameter: Bool
    public var description: String?

    public init(name: String, kind: String = "m", expression: String, description: String? = nil) {
        self.name = name
        self.kind = kind
        self.expression = expression
        self.description = description
        self.isParameter = NamedExpression.looksLikeParameter(expression)
    }

    /// Un paramètre M porte `meta [IsParameterQuery=true, …]`.
    static func looksLikeParameter(_ expression: String) -> Bool {
        let compact = expression.lowercased().filter { !$0.isWhitespace }
        return compact.contains("isparameterquery=true")
    }
}

public struct Role: Codable, Equatable, Sendable {
    public struct TablePermission: Codable, Equatable, Sendable {
        public var table: String
        public var filterExpression: String?

        public init(table: String, filterExpression: String?) {
            self.table = table
            self.filterExpression = filterExpression
        }
    }

    public var name: String
    public var modelPermission: String?
    public var tablePermissions: [TablePermission]

    public init(name: String, modelPermission: String? = nil, tablePermissions: [TablePermission] = []) {
        self.name = name
        self.modelPermission = modelPermission
        self.tablePermissions = tablePermissions
    }
}
