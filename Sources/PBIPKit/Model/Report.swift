import Foundation

/// Rapport, identique quel que soit le format source (PBIR ou PBIR-Legacy).
public struct Report: Codable, Equatable, Sendable {
    public enum Format: String, Codable, Sendable {
        case legacy, pbir
    }

    public var format: Format
    public var pages: [Page]
    public var bookmarks: [Bookmark]
    public var themeName: String?
    /// Filtres de niveau rapport.
    public var filters: [FieldRef]
    /// Mesures définies dans le rapport (et non dans le modèle).
    public var extensionMeasures: [ExtensionMeasure]

    public init(format: Format, pages: [Page] = [], bookmarks: [Bookmark] = [], themeName: String? = nil,
                filters: [FieldRef] = [], extensionMeasures: [ExtensionMeasure] = []) {
        self.format = format
        self.pages = pages
        self.bookmarks = bookmarks
        self.themeName = themeName
        self.filters = filters
        self.extensionMeasures = extensionMeasures
    }

    public var visualCount: Int { pages.reduce(0) { $0 + $1.visuals.count } }
}

public struct Page: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var order: Int
    public var width: Double
    public var height: Double
    public var visuals: [Visual]
    /// Filtres de niveau page.
    public var filters: [FieldRef]

    public init(id: String, displayName: String, order: Int, width: Double, height: Double,
                visuals: [Visual] = [], filters: [FieldRef] = []) {
        self.id = id
        self.displayName = displayName
        self.order = order
        self.width = width
        self.height = height
        self.visuals = visuals
        self.filters = filters
    }
}

public struct Visual: Codable, Equatable, Sendable {
    public var id: String
    /// `visualType` (`card`, `lineChart`…) ; `group` pour un groupe de visuels.
    public var type: String
    public var title: String?
    public var position: Position
    public var fields: [FieldRef]

    public init(id: String, type: String, title: String? = nil, position: Position, fields: [FieldRef] = []) {
        self.id = id
        self.type = type
        self.title = title
        self.position = position
        self.fields = fields
    }
}

public struct Position: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, z: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.width = width
        self.height = height
    }
}

/// Référence d'un visuel ou d'un filtre vers un objet du modèle.
public struct FieldRef: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case column, measure, hierarchyLevel
    }

    public var kind: Kind
    public var table: String
    /// Colonne, mesure, ou niveau (pour `hierarchyLevel`).
    public var name: String
    /// Rôle de projection (`Values`, `Category`…), `filter` ou `sort`.
    public var role: String
    /// Hiérarchie du niveau, pour `hierarchyLevel`.
    public var hierarchy: String?
    /// Colonne portant une hiérarchie de date automatique (`PropertyVariationSource`).
    public var variationColumn: String?

    public init(kind: Kind, table: String, name: String, role: String,
                hierarchy: String? = nil, variationColumn: String? = nil) {
        self.kind = kind
        self.table = table
        self.name = name
        self.role = role
        self.hierarchy = hierarchy
        self.variationColumn = variationColumn
    }

    /// `Table[Nom]`, ou `Table[Hiérarchie].[Niveau]`.
    public var displayName: String {
        if kind == .hierarchyLevel, let hierarchy {
            return "\(table)[\(hierarchy)].[\(name)]"
        }
        return "\(table)[\(name)]"
    }
}

public struct Bookmark: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct ExtensionMeasure: Codable, Equatable, Sendable {
    public var table: String
    public var name: String
    public var expression: String

    public init(table: String, name: String, expression: String) {
        self.table = table
        self.name = name
        self.expression = expression
    }
}
