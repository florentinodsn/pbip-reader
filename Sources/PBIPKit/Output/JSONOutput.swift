import Foundation

public enum OutputFormat: String, CaseIterable, Sendable {
    case text, json, markdown
}

/// Sortie JSON stable : clés triées, indentation fixe, barres obliques non échappées.
public enum JSONOutput {
    public static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(value)
            return String(decoding: data, as: UTF8.self) + "\n"
        } catch {
            // Les types sérialisés sont tous des structures simples : ne doit pas arriver.
            return "{\"error\": \"\(error)\"}\n"
        }
    }
}
