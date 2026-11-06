import Foundation

/// Minimal ordered JSON writer, ported from the Android SDK's Json object
/// (writer half only — response parsing rides JSONSerialization instead,
/// which Foundation provides on every platform including Linux).
///
/// Why not JSONEncoder/JSONSerialization for writing: neither guarantees key
/// order, and the wire-parity tests pin exact body strings against captured
/// production traffic. Insertion order also keeps cross-SDK diffs readable.
enum Json {

    /// Pre-serialized JSON embedded verbatim (nested objects/arrays).
    struct Raw: Equatable {
        let text: String
    }

    enum WriteError: Error {
        /// NaN/Infinity have no JSON encoding; refusing loudly beats emitting
        /// a body ee-web will 400.
        case nonFiniteNumber
        case unsupportedType(String)
    }

    /// `{"k":v,...}` in the given order.
    static func obj(_ fields: [(String, Any)]) throws -> String {
        var parts: [String] = []
        for (key, v) in fields {
            parts.append(string(key) + ":" + (try value(v)))
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    static func arr(_ items: [Raw]) -> String {
        "[" + items.map(\.text).joined(separator: ",") + "]"
    }

    static func string(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out + "\""
    }

    private static func value(_ v: Any) throws -> String {
        switch v {
        case let b as Bool: return b ? "true" : "false"
        case let s as String: return string(s)
        case let i as Int: return String(i)
        case let i as Int64: return String(i)
        case let d as Double:
            guard d.isFinite else { throw WriteError.nonFiniteNumber }
            return String(d)
        case let raw as Raw: return raw.text
        default: throw WriteError.unsupportedType(String(describing: type(of: v)))
        }
    }
}
