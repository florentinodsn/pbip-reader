import Foundation

/// Analyseur TMDL : lignes indentées → arbre de `TMDLNode`.
///
/// Grammaire (docs/NOTES.md § 4) :
/// - déclaration `<type> [<nom>] [= <propriété par défaut>]`, enfants et propriétés au niveau + 1 ;
/// - propriété `clé: valeur` ou indicateur booléen seul ;
/// - expression après `=` : même ligne, ou lignes suivantes indentées d'un niveau de plus que les
///   propriétés (déclaration + 2, propriété d'expression + 1), ou bloc entre ``` ;
/// - description : lignes `///` juste au-dessus d'une déclaration ;
/// - `ref <type> <nom>` : ordre des collections.
public struct TMDLParser {
    private var lexer: TMDLLexer
    private let lines: [TMDLLine]
    private var index = 0
    private let file: String
    private let report: (Diagnostic.Severity, String, String, Int?) -> Void

    /// - Parameters:
    ///   - file: chemin affiché dans les nœuds et diagnostics.
    ///   - report: reçoit (gravité, code, message, ligne).
    public init(text: String, file: String,
                report: @escaping (Diagnostic.Severity, String, String, Int?) -> Void = { _, _, _, _ in }) {
        var lexer = TMDLLexer(text: text)
        lines = lexer.lines()
        self.lexer = lexer
        self.file = file
        self.report = report
        if lexer.mixedIndentation {
            report(.warning, "tmdl.mixedIndentation", "File mixes tabs and spaces for indentation.", nil)
        }
    }

    /// Analyse tout le document et renvoie les nœuds de premier niveau.
    public mutating func parse() -> [TMDLNode] {
        let (nodes, properties) = parseBlock(level: 0)
        for p in properties {
            report(.warning, "tmdl.unexpectedProperty", "Property '\(p.name)' outside of any object.", p.line)
        }
        return nodes
    }

    // MARK: - Blocs

    private mutating func parseBlock(level: Int) -> ([TMDLNode], [TMDLProperty]) {
        var nodes: [TMDLNode] = []
        var properties: [TMDLProperty] = []
        var description: [String] = []

        while index < lines.count {
            let line = lines[index]
            if line.isBlank {
                if !description.isEmpty {
                    report(.warning, "tmdl.detachedDescription", "Description (///) is not directly above an object; ignored.", line.number)
                    description.removeAll()
                }
                index += 1
                continue
            }
            if line.level < level { break }
            if line.level > level {
                report(.warning, "tmdl.unexpectedIndentation", "Unexpected indentation; line ignored.", line.number)
                index += 1
                continue
            }

            if line.content.hasPrefix("///") {
                var text = line.content.dropFirst(3)
                if text.first == " " { text = text.dropFirst() }
                description.append(String(text))
                index += 1
                continue
            }

            switch classify(line.content) {
            case .property(let name, let value):
                index += 1
                properties.append(TMDLProperty(name: name, value: TMDLName.unquoteValue(value), isExpression: false, line: line.number))
                skipDeeperLines(than: level, context: name)
            case .flag(let name):
                index += 1
                properties.append(TMDLProperty(name: name, value: "", isExpression: false, line: line.number))
                skipDeeperLines(than: level, context: name)
            case .expressionProperty(let name, let rest):
                index += 1
                let value = parseExpression(rest, expressionLevel: level + 1, startLine: line.number)
                properties.append(TMDLProperty(name: name, value: value, isExpression: true, line: line.number))
            case .ref(let type, let name):
                index += 1
                nodes.append(TMDLNode(keyword: type, name: name, file: file, line: line.number))
                nodes[nodes.count - 1].isRef = true
            case .object(let keyword, let name, let rest):
                index += 1
                var node = TMDLNode(keyword: keyword, name: name, file: file, line: line.number)
                if !description.isEmpty {
                    node.description = description.joined(separator: "\n")
                }
                if !TMDLKeywords.objects.contains(keyword.lowercased()) {
                    node.isUnknown = true
                    report(.warning, "tmdl.unknownKeyword", "Unknown keyword '\(keyword)'; kept as a generic object.", line.number)
                }
                if let rest {
                    node.defaultValue = parseExpression(rest, expressionLevel: level + 2, startLine: line.number)
                }
                let (children, props) = parseBlock(level: level + 1)
                node.children = children
                node.properties = props
                nodes.append(node)
            case .invalid:
                report(.warning, "tmdl.syntax", "Cannot parse line: \(line.content)", line.number)
                index += 1
            }
            description.removeAll()
        }
        if !description.isEmpty {
            report(.warning, "tmdl.detachedDescription", "Description (///) at the end of a block; ignored.", nil)
        }
        return (nodes, properties)
    }

    /// Une propriété `clé: valeur` tient sur une ligne : des lignes plus indentées sont ignorées.
    private mutating func skipDeeperLines(than level: Int, context: String) {
        while index < lines.count, !lines[index].isBlank, lines[index].level > level {
            report(.warning, "tmdl.unexpectedIndentation", "Unexpected indented line after property '\(context)'; ignored.", lines[index].number)
            index += 1
        }
    }

    // MARK: - Expressions

    /// `index` pointe sur la ligne qui suit la déclaration.
    private mutating func parseExpression(_ rest: String, expressionLevel: Int, startLine: Int) -> String {
        let first = rest.trimmingCharacters(in: .whitespaces)

        if first.hasPrefix("```") {
            return parseBacktickExpression(String(first.dropFirst(3)), startLine: startLine)
        }

        // Lignes de l'expression : au moins `expressionLevel`. Desktop écrit `source =` d'une partition
        // avec l'expression deux niveaux plus bas, l'exemple de la doc un seul : on retire donc
        // l'indentation commune réelle (le plus petit niveau rencontré), jamais moins que le seuil.
        var body: [TMDLLine?] = []
        while index < lines.count {
            let line = lines[index]
            if line.isBlank {
                // Une ligne vide fait partie de l'expression seulement si l'expression continue après.
                guard let next = nextNonBlank(from: index), lines[next].level >= expressionLevel else { break }
                for _ in index..<next { body.append(nil) }
                index = next
                continue
            }
            guard line.level >= expressionLevel else { break }
            body.append(line)
            index += 1
        }
        let margin = body.compactMap { $0?.level }.min() ?? expressionLevel
        var out: [String] = first.isEmpty ? [] : [first]
        for line in body {
            out.append(line.map { lexer.strip(levels: margin, from: $0.raw).trimmingTrailingWhitespace() } ?? "")
        }
        return ExpressionText.normalize(out.joined(separator: "\n"))
    }

    /// Bloc ``` : lu tel quel ; la ligne de fermeture fixe la marge gauche.
    private mutating func parseBacktickExpression(_ afterOpening: String, startLine: Int) -> String {
        if let close = afterOpening.range(of: "```") {
            return String(afterOpening[..<close.lowerBound])
        }
        var collected: [String] = []
        let opening = afterOpening.trimmingCharacters(in: .whitespaces)
        if !opening.isEmpty { collected.append(opening) }

        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.content.hasPrefix("```") {
                let margin = line.raw.prefix { $0 == " " || $0 == "\t" }.count
                let body = collected.map { raw -> String in
                    var removed = 0
                    var s = Substring(raw)
                    while removed < margin, let c = s.first, c == " " || c == "\t" {
                        s = s.dropFirst()
                        removed += 1
                    }
                    return String(s)
                }
                return body.joined(separator: "\n")
            }
            collected.append(line.raw)
        }
        report(.warning, "tmdl.unclosedBackticks", "Expression opened with ``` is never closed.", startLine)
        return ExpressionText.normalize(collected.joined(separator: "\n"))
    }

    private func nextNonBlank(from start: Int) -> Int? {
        var i = start
        while i < lines.count {
            if !lines[i].isBlank { return i }
            i += 1
        }
        return nil
    }

    // MARK: - Classification d'une ligne

    enum LineKind: Equatable {
        case object(keyword: String, name: String?, rest: String?)
        case property(name: String, value: String)
        case expressionProperty(name: String, rest: String)
        case flag(String)
        case ref(type: String, name: String)
        case invalid
    }

    func classify(_ content: String) -> LineKind {
        guard let word = TMDLName.leadingIdentifier(content) else { return .invalid }
        let after = content.dropFirst(word.count)
        let trimmed = after.drop { $0 == " " || $0 == "\t" }

        if trimmed.first == ":" {
            return .property(name: word, value: String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        if trimmed.isEmpty {
            let known = TMDLKeywords.objects.contains(word.lowercased())
            return known || nextLineIsDeeper() ? .object(keyword: word, name: nil, rest: nil) : .flag(word)
        }
        if trimmed.first == "=" {
            let rest = String(trimmed.dropFirst())
            return TMDLKeywords.objects.contains(word.lowercased())
                ? .object(keyword: word, name: nil, rest: rest)
                : .expressionProperty(name: word, rest: rest)
        }
        guard after.first == " " || after.first == "\t" else { return .invalid }

        if word.lowercased() == "ref" {
            guard let type = TMDLName.leadingIdentifier(String(trimmed)) else { return .invalid }
            let nameText = trimmed.dropFirst(type.count).trimmingCharacters(in: .whitespaces)
            let (name, _) = TMDLName.parseName(nameText)
            return .ref(type: type, name: name ?? nameText)
        }

        let (name, remainder) = TMDLName.parseName(String(trimmed))
        let rest = remainder.trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return .object(keyword: word, name: name, rest: nil) }
        if rest.first == "=" { return .object(keyword: word, name: name, rest: String(rest.dropFirst())) }
        return .object(keyword: word, name: name, rest: nil)
    }

    private func nextLineIsDeeper() -> Bool {
        guard let next = nextNonBlank(from: index + 1) else { return false }
        return lines[next].level > lines[index].level
    }
}

/// Noms TMDL : apostrophes, doublement, notation pointée.
public enum TMDLName {
    static func leadingIdentifier(_ text: String) -> String? {
        var result = ""
        for c in text {
            guard c.isLetter || c == "_" || (!result.isEmpty && c.isNumber) else { break }
            result.append(c)
        }
        return result.isEmpty ? nil : result
    }

    /// Lit un nom en tête de texte. Renvoie le nom (sans apostrophes) et la suite.
    /// Non entre apostrophes, le nom s'arrête au premier `=` (interdit dans un nom non cité).
    static func parseName(_ text: String) -> (String?, String) {
        guard let first = text.first else { return (nil, "") }
        if first == "'" {
            var name = ""
            var i = text.index(after: text.startIndex)
            while i < text.endIndex {
                let c = text[i]
                if c == "'" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "'" {
                        name.append("'")
                        i = text.index(after: next)
                        continue
                    }
                    return (name, String(text[next...]))
                }
                name.append(c)
                i = text.index(after: i)
            }
            return (name, "")
        }
        if let eq = text.firstIndex(of: "=") {
            let name = text[..<eq].trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? nil : name, String(text[eq...]))
        }
        return (text.trimmingCharacters(in: .whitespaces), "")
    }

    /// `'Table 1'.'Column 1'`, `Ventes.Date` → composants sans apostrophes.
    public static func splitQualified(_ text: String) -> [String] {
        var parts: [String] = []
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        while !rest.isEmpty {
            if rest.first == "'" {
                let (name, remainder) = parseName(String(rest))
                parts.append(name ?? "")
                rest = Substring(remainder)
            } else if let dot = rest.firstIndex(of: ".") {
                parts.append(String(rest[..<dot]).trimmingCharacters(in: .whitespaces))
                rest = rest[dot...]
            } else {
                parts.append(String(rest).trimmingCharacters(in: .whitespaces))
                rest = ""
            }
            if rest.first == "." { rest = rest.dropFirst() } else if !rest.isEmpty {
                rest = rest.drop { $0 != "." }
                if rest.first == "." { rest = rest.dropFirst() }
            }
        }
        return parts
    }

    /// Référence simple (`column: 'Category Order'`) → nom sans apostrophes.
    public static func unquoteReference(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.first == "'" { return parseName(t).0 ?? t }
        return t
    }

    /// Valeur de propriété : guillemets doubles optionnels, `""` échappe `"`.
    static func unquoteValue(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") else { return t }
        return String(t.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
    }
}

/// Normalisation commune aux expressions (DAX, M) des deux formats de modèle.
public enum ExpressionText {
    /// Lignes d'espaces → vides ; lignes vides en tête et en fin retirées.
    public static func normalize(_ text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? "" : $0 }
        while lines.first == "" { lines.removeFirst() }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
