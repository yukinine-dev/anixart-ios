import SwiftUI
import AnixartKit

struct ReleaseCredit: Hashable {
    let title: String
    let value: String
    let scope: SearchScope

    var url: URL { URL(string: "anixart-credit://search/\(scope.rawValue)")! }

    static func entries(for release: Release) -> [ReleaseCredit] {
        let values: [(String, String?, SearchScope)] = [
            ("Студия", release.studio, .studio),
            ("автор", release.author, .author),
            ("режиссёр", release.director, .director)
        ]
        return values.compactMap { title, raw, scope in
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return ReleaseCredit(title: title, value: value, scope: scope)
        }
    }

    static func text(for entries: [ReleaseCredit]) -> AttributedString {
        var result = AttributedString()
        for (index, entry) in entries.enumerated() {
            result += AttributedString((index == 0 ? "" : ", ") + entry.title + " ")
            var value = AttributedString(entry.value)
            value.underlineStyle = .single
            value.link = entry.url
            result += value
        }
        return result
    }
}

/// One naturally wrapping fact, with an independent search link for each credit.
@MainActor
struct ReleaseCreditsLine: View {
    @Environment(AppEnvironment.self) private var env
    let release: Release
    let viewer: ProfileViewerKey?
    @State private var selected: ReleaseCredit?

    var body: some View {
        let entries = ReleaseCredit.entries(for: release)
        if !entries.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                // Fitted into the icon column: at title3 the symbol is wider than 26 pt and
                // ran into the word «Студия».
                Image(systemName: "person.3").resizable().scaledToFit()
                    .frame(width: 24, height: 22).foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .leading).accessibilityHidden(true)
                Text(ReleaseCredit.text(for: entries))
                    .font(.ax(.subheadline))
                    .tint(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .environment(\.openURL, OpenURLAction { url in
                if let viewer, viewer == env.session.viewerKey {
                    selected = entries.first { $0.url == url }
                }
                return .handled
            })
            .navigationDestination(item: $selected) { credit in
                if let viewer {
                    SourceMaterialSearchView(query: credit.value, scope: credit.scope,
                                             title: "\(credit.title): \(credit.value)", viewer: viewer)
                }
            }
        }
    }
}
