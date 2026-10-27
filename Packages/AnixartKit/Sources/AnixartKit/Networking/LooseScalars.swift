import Foundation

/// Scalar accessors that tolerate the server sending a value in the wrong JSON
/// type.
///
/// This exists because of one field. `config/toggles` answers with
/// `"searchBarIconTint": "false"` -- a string, sitting among two dozen flags the
/// same response sends as real booleans. Jackson coerces that silently, so the
/// Android app never noticed; Swift's synthesised `init(from:)` does not, and a
/// single mistyped flag threw away the *whole* response. Which meant the app
/// also lost `kodikAdIframeUrl`, `kodikVideoLinksUrl` and `kodikIframeAd` from
/// the same payload, and the web player kept loading Kodik's page directly.
///
/// Only the config responses decode this way (see `LENIENT` in
/// `Tools/generate-models.py`): they are grab-bags of server-controlled scalars
/// that are edited by hand on the server, so a type can change under us at any
/// time, and losing one flag must not cost the other fifty.
extension KeyedDecodingContainer {
    /// `true`/`false`, `"true"`/`"false"`, `"1"`/`"0"`, `1`/`0`.
    func looseBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            switch text.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return number != 0 }
        return nil
    }

    func looseInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Int(text) }
        if let number = try? decodeIfPresent(Double.self, forKey: key) { return Int(number) }
        return nil
    }

    func looseDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    func looseString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return String(number) }
        if let flag = try? decodeIfPresent(Bool.self, forKey: key) { return String(flag) }
        return nil
    }

    func looseStrings(_ key: Key) -> [String]? {
        if let value = try? decodeIfPresent([String].self, forKey: key) { return value }
        if let single = try? decodeIfPresent(String.self, forKey: key) { return [single] }
        return nil
    }
}
