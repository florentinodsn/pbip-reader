import Foundation

/// Découpage simple d'une expression DAX ou M pour la coloration. Sans dépendance d'interface :
/// l'application associe une couleur à chaque `Kind`.
public enum SyntaxTokenizer {
    public enum Language: Sendable {
        case dax, m
    }

    public enum Kind: String, Sendable {
        case plain, keyword, function, string, number, comment, reference, table
    }

    public struct Token: Equatable, Sendable {
        public var kind: Kind
        public var text: String
    }

    static let daxKeywords: Set<String> = [
        "VAR", "RETURN", "IN", "NOT", "AND", "OR", "TRUE", "FALSE", "DEFINE", "EVALUATE", "MEASURE", "ORDER", "BY", "ASC", "DESC",
    ]
    static let mKeywords: Set<String> = [
        "let", "in", "each", "if", "then", "else", "true", "false", "null", "try", "otherwise", "type", "meta",
        "and", "or", "not", "as", "is", "section", "shared",
    ]

    /// La concaténation des `text` redonne exactement l'expression d'origine.
    public static func tokenize(_ text: String, language: Language) -> [Token] {
        let chars = Array(text)
        var tokens: [Token] = []
        var i = 0

        func emit(_ kind: Kind, _ start: Int) {
            let piece = String(chars[start..<i])
            if kind == .plain, let last = tokens.last, last.kind == .plain {
                tokens[tokens.count - 1].text += piece
            } else {
                tokens.append(Token(kind: kind, text: piece))
            }
        }
        func at(_ offset: Int) -> Character? { i + offset < chars.count ? chars[i + offset] : nil }
        func readUntilDelimiter(_ close: Character) {
            i += 1
            while i < chars.count {
                if chars[i] == close {
                    if at(1) == close { i += 2; continue }
                    i += 1
                    return
                }
                i += 1
            }
        }

        while i < chars.count {
            let start = i
            let c = chars[i]
            if (c == "/" && at(1) == "/") || (language == .dax && c == "-" && at(1) == "-") {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                emit(.comment, start)
            } else if c == "/" && at(1) == "*" {
                i += 2
                while i < chars.count, !(chars[i] == "*" && at(1) == "/") { i += 1 }
                i = min(i + 2, chars.count)
                emit(.comment, start)
            } else if c == "\"" {
                readUntilDelimiter("\"")
                emit(.string, start)
            } else if language == .dax && c == "'" {
                readUntilDelimiter("'")
                emit(.table, start)
            } else if language == .dax && c == "[" {
                readUntilDelimiter("]")
                emit(.reference, start)
            } else if language == .m && c == "#" && at(1) == "\"" {
                // Identifiant M cité : #"Nom avec espaces".
                i += 1
                readUntilDelimiter("\"")
                emit(.reference, start)
            } else if c.isNumber {
                while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
                emit(.number, start)
            } else if c.isLetter || c == "_" {
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "." { i += 1 }
                let word = String(chars[start..<i])
                let isKeyword = language == .dax ? daxKeywords.contains(word.uppercased()) : mKeywords.contains(word)
                var next = i
                while next < chars.count, chars[next] == " " { next += 1 }
                if isKeyword {
                    emit(.keyword, start)
                } else if next < chars.count, chars[next] == "(" {
                    emit(.function, start)
                } else {
                    emit(language == .dax ? .table : .plain, start)
                }
            } else {
                i += 1
                emit(.plain, start)
            }
        }
        return tokens
    }
}
