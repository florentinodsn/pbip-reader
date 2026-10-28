import Foundation

/// Arbre des dossiers d'affichage des mesures d'une table.
/// `displayFolder` sépare les sous-dossiers par `\` ; plusieurs dossiers sont séparés par `;`
/// (la mesure apparaît alors dans chacun).
public struct MeasureFolder: Equatable, Sendable {
    public var name: String
    /// Chemin complet, `\` entre les niveaux ; vide pour la racine.
    public var path: String
    public var folders: [MeasureFolder]
    public var measures: [String]

    public init(name: String = "", path: String = "", folders: [MeasureFolder] = [], measures: [String] = []) {
        self.name = name
        self.path = path
        self.folders = folders
        self.measures = measures
    }

    public var measureCount: Int { measures.count + folders.reduce(0) { $0 + $1.measureCount } }

    /// Dossiers et mesures triés par nom, sans tenir compte de la casse.
    public static func tree(_ measures: [Measure]) -> MeasureFolder {
        var root = MeasureFolder()
        for m in measures {
            let paths = (m.displayFolder ?? "")
                .split(separator: ";")
                .map { $0.split(separator: "\\").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                .filter { !$0.isEmpty }
            if paths.isEmpty {
                root.measures.append(m.name)
            }
            for path in paths {
                root.insert(m.name, at: path[...])
            }
        }
        root.sort()
        return root
    }

    mutating func insert(_ measure: String, at path: ArraySlice<String>) {
        guard let first = path.first else {
            if !measures.contains(measure) { measures.append(measure) }
            return
        }
        let index = folders.firstIndex { $0.name.caseInsensitiveCompare(first) == .orderedSame } ?? {
            folders.append(MeasureFolder(name: first, path: self.path.isEmpty ? first : self.path + "\\" + first))
            return folders.count - 1
        }()
        folders[index].insert(measure, at: path.dropFirst())
    }

    mutating func sort() {
        let before = { (a: String, b: String) in a.caseInsensitiveCompare(b) == .orderedAscending }
        measures.sort(by: before)
        folders.sort { before($0.name, $1.name) }
        for i in folders.indices { folders[i].sort() }
    }
}
