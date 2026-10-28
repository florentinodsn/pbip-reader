import Foundation

/// Une ligne physique d'un document TMDL, avec son niveau d'indentation.
struct TMDLLine: Equatable {
    /// Numéro de ligne, à partir de 1.
    var number: Int
    /// Ligne complète, sans fin de ligne.
    var raw: String
    /// Niveau d'indentation (tabulations, ou groupes d'espaces).
    var level: Int
    /// Contenu après l'indentation, espaces de fin retirés.
    var content: String

    var isBlank: Bool { content.isEmpty }
}

/// Découpe un document TMDL en lignes et calcule leur indentation.
///
/// La doc impose une tabulation par niveau ; on accepte aussi des espaces, à condition qu'ils
/// soient utilisés de façon cohérente : l'unité est le plus petit retrait en espaces du fichier.
struct TMDLLexer {
    let text: String

    /// Nombre d'espaces équivalant à un niveau (fichiers indentés en espaces).
    private(set) var spaceUnit = 4
    private(set) var mixedIndentation = false

    init(text: String) {
        self.text = text
    }

    mutating func lines() -> [TMDLLine] {
        // CRLF, LF et CR seul sont tous acceptés.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var rawLines = normalized.components(separatedBy: "\n")
        if rawLines.last == "" { rawLines.removeLast() }

        var usesTabs = false
        var usesSpaces = false
        var smallestSpaces = Int.max
        for raw in rawLines where !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            let lead = raw.prefix { $0 == " " || $0 == "\t" }
            if lead.first == "\t" { usesTabs = true }
            if lead.first == " " {
                usesSpaces = true
                if !lead.contains("\t") { smallestSpaces = min(smallestSpaces, lead.count) }
            }
        }
        mixedIndentation = usesTabs && usesSpaces
        if !usesTabs, usesSpaces, smallestSpaces != Int.max { spaceUnit = smallestSpaces }

        return rawLines.enumerated().map { index, raw in
            let lead = raw.prefix { $0 == " " || $0 == "\t" }
            let content = String(raw.dropFirst(lead.count)).trimmingTrailingWhitespace()
            return TMDLLine(number: index + 1, raw: raw, level: content.isEmpty ? 0 : level(of: lead), content: content)
        }
    }

    func level<S: StringProtocol>(of whitespace: S) -> Int {
        var level = 0
        var spaces = 0
        for c in whitespace {
            if c == "\t" {
                level += 1
                spaces = 0
            } else {
                spaces += 1
                if spaces == spaceUnit {
                    level += 1
                    spaces = 0
                }
            }
        }
        return level
    }

    /// Retire `levels` niveaux d'indentation en tête de ligne, et pas plus.
    func strip(levels: Int, from raw: String) -> String {
        var removed = 0
        var spaces = 0
        var index = raw.startIndex
        while index < raw.endIndex, removed < levels {
            let c = raw[index]
            if c == "\t" {
                removed += 1
                spaces = 0
            } else if c == " " {
                spaces += 1
                if spaces == spaceUnit {
                    removed += 1
                    spaces = 0
                }
            } else {
                break
            }
            index = raw.index(after: index)
        }
        return String(raw[index...])
    }
}

extension String {
    func trimmingTrailingWhitespace() -> String {
        var s = Substring(self)
        while let last = s.last, last == " " || last == "\t" { s = s.dropLast() }
        return String(s)
    }
}
