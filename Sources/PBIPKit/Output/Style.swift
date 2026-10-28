import Foundation

/// Mise en forme du texte : couleurs ANSI optionnelles.
public struct Style: Sendable {
    public var color: Bool

    public init(color: Bool) {
        self.color = color
    }

    func wrap(_ text: String, _ code: String) -> String {
        color ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    func bold(_ s: String) -> String { wrap(s, "1") }
    func dim(_ s: String) -> String { wrap(s, "2") }
    func red(_ s: String) -> String { wrap(s, "31") }
    func yellow(_ s: String) -> String { wrap(s, "33") }
    func blue(_ s: String) -> String { wrap(s, "34") }
    func cyan(_ s: String) -> String { wrap(s, "36") }
    func green(_ s: String) -> String { wrap(s, "32") }

    func severity(_ severity: Diagnostic.Severity) -> String {
        let label = severity.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
        switch severity {
        case .error: return red(label)
        case .warning: return yellow(label)
        case .info: return blue(label)
        }
    }
}

/// Utilitaires communs aux sorties texte et Markdown.
enum Format {
    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    static func indent(_ text: String, _ prefix: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : prefix + $0 }
            .joined(separator: "\n")
    }

    static func plural(_ count: Int, _ word: String) -> String {
        "\(count) \(word)\(count == 1 ? "" : "s")"
    }

    /// Cellule de tableau Markdown : pas de barre verticale ni de retour à la ligne.
    static func cell(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        return text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>")
    }

    static func reference(_ ref: DatasetReference) -> String {
        switch ref.kind {
        case .byPath: return "byPath \(ref.path ?? "?")"
        case .byConnection: return "byConnection \(ref.modelName ?? "(unknown model)")"
        }
    }
}
