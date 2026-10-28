import Foundation

/// Référence trouvée dans une expression DAX : `'Table'[Nom]`, `Table[Nom]` ou `[Nom]`.
public struct DAXReference: Hashable, Sendable {
    public var table: String?
    public var name: String
}

/// Balayage lexical simple d'une expression DAX, pour le lignage.
///
/// Ce n'est pas un analyseur DAX : il ignore commentaires et chaînes, puis relève les noms entre
/// crochets, qualifiés ou non par une table. Une variable de table (`t[col]`) est relevée comme
/// une table nommée `t` : c'est à l'appelant d'ignorer les tables inconnues.
public enum DAXScanner {
    public static func references(in expression: String) -> [DAXReference] {
        let chars = Array(expression)
        var refs: [DAXReference] = []
        var i = 0
        var lastTable: (name: String, end: Int)?

        func peek(_ offset: Int) -> Character? {
            i + offset < chars.count ? chars[i + offset] : nil
        }

        /// Lit un nom délimité, où le délimiteur doublé vaut un caractère.
        func readDelimited(_ close: Character) -> String {
            var out = ""
            i += 1
            while i < chars.count {
                if chars[i] == close {
                    if peek(1) == close {
                        out.append(close)
                        i += 2
                        continue
                    }
                    i += 1
                    return out
                }
                out.append(chars[i])
                i += 1
            }
            return out
        }

        while i < chars.count {
            let c = chars[i]
            if (c == "/" && peek(1) == "/") || (c == "-" && peek(1) == "-") {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/" && peek(1) == "*" {
                i += 2
                while i < chars.count, !(chars[i] == "*" && peek(1) == "/") { i += 1 }
                i += 2
                continue
            }
            if c == "\"" {
                _ = readDelimited("\"")
                continue
            }
            if c == "'" {
                let name = readDelimited("'")
                lastTable = (name, i)
                continue
            }
            if c == "[" {
                let start = i
                let name = readDelimited("]")
                let table = lastTable.flatMap { $0.end == start ? $0.name : nil }
                refs.append(DAXReference(table: table, name: name))
                lastTable = nil
                continue
            }
            if c.isLetter || c == "_" {
                var word = ""
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "." {
                    word.append(chars[i])
                    i += 1
                }
                lastTable = (word, i)
                continue
            }
            i += 1
        }
        return refs
    }
}
