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
            // The line opens a sentence, so only its first credit is capitalised.
            let title = index == 0 ? entry.title.prefix(1).uppercased() + entry.title.dropFirst() : entry.title
            result += AttributedString((index == 0 ? "" : ", ") + title + " ")
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
            // Same icon column and text size as the other fact lines, so the text
            // starts on exactly the same x.
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "person.3").resizable().scaledToFit()
                    .frame(width: 18, height: 16).foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .center).accessibilityHidden(true)
                Text(ReleaseCredit.text(for: entries))
                    .font(.ax(.footnote))
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
