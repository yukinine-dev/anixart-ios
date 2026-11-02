import Foundation

extension Release {
    /// `format_source_link` uses source#<label>, not a web URL or a genre.
    /// Only names already verified in the APK's array/sources become links;
    /// an unknown server value remains readable text, never a guessed route.
    public var sourceMaterialSearch: SourceMaterial? {
        guard let source else { return nil }
        return SourceMaterial(rawValue: source.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
