import Foundation

/// Arbre JSON générique : les propriétés inconnues sont simplement ignorées par les lecteurs.
public enum JSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public static func parse(_ data: Data) throws -> JSON {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSON(any: any)
    }

    public static func parse(_ text: String) throws -> JSON {
        try parse(Data(text.utf8))
    }

    init(any: Any) {
        switch any {
        case let n as NSNumber:
            // JSONSerialization renvoie les booléens comme NSNumber : on les distingue par leur type CF.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case let s as String:
            self = .string(s)
        case let a as [Any]:
            self = .array(a.map(JSON.init(any:)))
        case let d as [String: Any]:
            self = .object(d.mapValues(JSON.init(any:)))
        default:
            self = .null
        }
    }

    public subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public subscript(index: Int) -> JSON? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    public var int: Int? { double.map { Int($0) } }

    public var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s): return s.lowercased() == "true" ? true : (s.lowercased() == "false" ? false : nil)
        default: return nil
        }
    }

    public var array: [JSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var object: [String: JSON]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Accès par chemin : `json.at("visual", "query", "queryState")`.
    public func at(_ keys: String...) -> JSON? {
        var current: JSON? = self
        for key in keys {
            current = current?[key]
        }
        return current
    }
}
