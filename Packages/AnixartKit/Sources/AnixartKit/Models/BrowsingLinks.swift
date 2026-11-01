import Foundation

/// Exact branches of DiscoverFragment.onInterest in the original APK:
/// 1 = release ID, 2 = URL, 3 = collection ID. Unknown actions are not guessed.
public enum DiscoverBannerAction: Hashable, Sendable {
    case release(Int)
    case web(URL)
    case collection(Int)
}

extension Interesting {
    public var destination: DiscoverBannerAction? {
        guard isHidden != true else { return nil }
        switch type {
        case 1: return BrowsingLinkValue.positiveID(action).map(DiscoverBannerAction.release)
        case 2: return BrowsingLinkValue.webURL(action).map(DiscoverBannerAction.web)
        case 3: return BrowsingLinkValue.positiveID(action).map(DiscoverBannerAction.collection)
        default: return nil
        }
    }
}

/// ReleaseVideoBanner's ACTION_VIDEO_CATEGORY = 0 and ACTION_URL = 1.
/// `value` carries the category ID or URL; `name` is only its displayed title.
public enum ReleaseVideoBannerAction: Hashable, Sendable {
    case category(Int)
    case web(URL)
}

extension ReleaseVideoBanner {
    public var destination: ReleaseVideoBannerAction? {
        switch actionId {
        case 0: return BrowsingLinkValue.positiveID(value).map(ReleaseVideoBannerAction.category)
        case 1: return BrowsingLinkValue.webURL(value).map(ReleaseVideoBannerAction.web)
        default: return nil
        }
    }
}

extension ReleaseVideo {
    /// An invalid preferred URL must not suppress a valid fallback URL or open an
    /// empty full-screen player. Trailers remain web players, not episode streams.
    public var playbackURL: URL? {
        BrowsingLinkValue.webURL(playerUrl) ?? BrowsingLinkValue.webURL(url)
    }
}

extension ReleaseStreamingPlatform {
    public var destinationURL: URL? { BrowsingLinkValue.webURL(url) }
}

private enum BrowsingLinkValue {
    static func positiveID(_ text: String?) -> Int? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let id = Int(text), id > 0 else { return nil }
        return id
    }

    static func webURL(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

extension Related {
    public var displayName: String { (nameRu?.isEmpty == false ? nameRu : nil) ?? "Франшиза" }

    public var posterURLs: [URL] {
        var seen = Set<URL>()
        let urls = (images ?? []).compactMap(AnixartURL.image)
        let candidates = urls.isEmpty ? [AnixartURL.image(image)].compactMap { $0 } : urls
        return candidates.filter { seen.insert($0).inserted }
    }

    public var releaseCountText: String? {
        guard let releaseCount, releaseCount >= 0 else { return nil }
        let word: String
        if (11...14).contains(releaseCount % 100) { word = "релизов" }
        else {
            switch releaseCount % 10 {
            case 1: word = "релиз"
            case 2...4: word = "релиза"
            default: word = "релизов"
            }
        }
        return "\(releaseCount) \(word) во франшизе"
    }
}

public struct ReleaseTitleField: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case russian, original, alternate
    }
    public let kind: Kind
    public let value: String
    public var id: Kind { kind }
    public var label: String {
        switch kind {
        case .russian: return "Название"
        case .original: return "Оригинальное название"
        case .alternate: return "Альтернативные названия"
        }
    }
}

extension Release {
    /// Copy controls must expose only titles actually returned by the server,
    /// never the displayTitle fallback ("Без названия").
    public var titleFields: [ReleaseTitleField] {
        let candidates: [(ReleaseTitleField.Kind, String?)] = [
            (.russian, titleRu), (.original, titleOriginal), (.alternate, titleAlt)
        ]
        return candidates.compactMap { kind, value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return ReleaseTitleField(kind: kind, value: value)
        }
    }
}
