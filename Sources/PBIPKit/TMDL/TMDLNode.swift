import Foundation

/// Propriété d'un objet TMDL : `clé: valeur`, `clé = expression`, ou indicateur booléen seul.
public struct TMDLProperty: Equatable, Sendable {
    public var name: String
    public var value: String
    /// Vrai pour `clé = expression` (valeur lue telle quelle, éventuellement multi-ligne).
    public var isExpression: Bool
    public var line: Int
}

/// Nœud de l'arbre TMDL. Les mots-clés inconnus restent des nœuds génériques.
public struct TMDLNode: Equatable, Sendable {
    /// Mot-clé tel qu'écrit (`table`, `measure`…).
    public var keyword: String
    /// Nom, apostrophes retirées ; absent pour `database`, `dataAccessOptions`…
    public var name: String?
    /// Propriété par défaut, après `=` sur la ligne de déclaration.
    public var defaultValue: String?
    public var description: String?
    public var properties: [TMDLProperty] = []
    public var children: [TMDLNode] = []
    /// `ref table X` : référence d'ordre, sans contenu.
    public var isRef = false
    /// Mot-clé absent de la liste connue.
    public var isUnknown = false
    public var file: String
    public var line: Int

    /// Les mots-clés TMDL sont insensibles à la casse à la lecture.
    public var kind: String { keyword.lowercased() }

    public func property(_ name: String) -> String? {
        properties.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Booléen : mot seul (`isHidden`) ou `isHidden: true`.
    public func flag(_ name: String) -> Bool? {
        guard let value = property(name) else { return nil }
        switch value.lowercased() {
        case "", "true": return true
        case "false": return false
        default: return nil
        }
    }

    public func children(_ kind: String) -> [TMDLNode] {
        children.filter { $0.kind == kind.lowercased() && !$0.isRef }
    }
}

/// Mots-clés d'objets TOM reconnus. Liste établie à partir de la doc TMDL et des objets TOM
/// documentés ; un mot-clé absent produit un avertissement mais reste lu.
enum TMDLKeywords {
    static let objects: Set<String> = [
        "database", "model", "table", "column", "measure", "hierarchy", "level", "partition",
        "relationship", "expression", "role", "tablepermission", "columnpermission", "member",
        "perspective", "perspectivetable", "perspectivecolumn", "perspectivemeasure", "perspectivehierarchy",
        "culture", "cultureinfo", "linguisticmetadata", "translation", "objecttranslation",
        "annotation", "extendedproperty", "changedproperty", "excludedartifact",
        "calculationgroup", "calculationitem", "multipleoremptyselectionexpression", "noselectionexpression",
        "formatstringdefinition", "detailrowsdefinition", "datacoveragedefinition", "kpi",
        "variation", "refreshpolicy", "alternateof", "datasource", "querygroup", "function",
        "dataaccessoptions", "attributehierarchy", "relatedcolumndetails", "groupbycolumn",
        "set", "bindinginfo", "calendar", "calendarcolumngroup", "timeunitcolumnassociation",
        "analyticsaimetadata", "parameter",
    ]
}
