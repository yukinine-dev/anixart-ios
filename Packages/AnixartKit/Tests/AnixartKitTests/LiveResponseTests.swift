import XCTest
@testable import AnixartKit

/// Decodes real API responses saved by CI, so a shape the APK did not reveal
/// fails here with its exact coding path rather than as an error banner on a
/// screen.
///
/// Skipped unless `ANIXART_LIVE_DIR` points at a directory of saved responses.
/// The workflow's `probe` job fills it; nothing here ever touches the network,
/// so the usual test run stays offline and deterministic.
///
/// Naming: each file is `<kind>-<anything>.json`, where `<kind>` picks the type
/// to decode it as.
final class LiveResponseTests: XCTestCase {
    private static let decoders: [String: (Data) throws -> String] = [
        "release": { try summary(ReleaseResponse.self, $0) { "release \($0.release?.id as Any)" } },
        "episodes": { try summary(EpisodeResponse.self, $0) { "\($0.episodes?.count ?? 0) episodes" } },
        "types": { try summary(TypesResponse.self, $0) { "\($0.types?.count ?? 0) types" } },
        "sources": { try summary(SourcesResponse.self, $0) { "\($0.sources?.count ?? 0) sources" } },
        "profile": { try summary(ProfileResponse.self, $0) { "profile \($0.profile?.id as Any)" } },
        "profiles": { try summary(PageableResponse<Profile>.self, $0) { "\($0.content?.count ?? 0) profiles" } },
        "filter": { try summary(PageableResponse<Release>.self, $0) { "\($0.content?.count ?? 0) releases" } },
        "comments": { try summary(PageableResponse<ReleaseComment>.self, $0) { "\($0.content?.count ?? 0) comments" } },
        "collections": { try summary(PageableResponse<ReleaseCollection>.self, $0) { "\($0.content?.count ?? 0) collections" } },
        // Not Anixart's: the release AniLibria returns for the id Anixart puts
        // in its Libria URLs, which is where the built-in player's stream
        // actually comes from.
        "libria": {
            try summary(AniLibriaStreamSource.ReleasePayload.self, $0) { release in
                let episodes = release.episodes ?? []
                let rungs = episodes.first?.streams.keys.sorted().map(String.init).joined(separator: "/") ?? "-"
                return "release \(release.id as Any), \(episodes.count) episodes, first offers \(rungs)"
            }
        }
    ]

    private static func summary<T: Decodable>(
        _ type: T.Type,
        _ data: Data,
        _ describe: (T) -> String
    ) throws -> String {
        describe(try JSONDecoder().decode(type, from: data))
    }

    func testDecodesSavedLiveResponses() throws {
        guard let directory = ProcessInfo.processInfo.environment["ANIXART_LIVE_DIR"],
              !directory.isEmpty
        else {
            throw XCTSkip("ANIXART_LIVE_DIR is not set; live responses are a CI-only check")
        }

        let url = URL(fileURLWithPath: directory, isDirectory: true)
        let files = try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(files.isEmpty, "no saved responses in \(directory)")

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let kind = name.split(separator: "-").first.map(String.init) ?? name
            guard let decode = Self.decoders[kind] else {
                XCTFail("\(name): no decoder registered for kind '\(kind)'")
                continue
            }

            let data = try Data(contentsOf: file)
            do {
                print("live \(name): \(try decode(data))")
            } catch {
                XCTFail("\(name) failed to decode: \(Self.describe(error))")
            }
        }
    }

    /// `DecodingError`'s own description buries the coding path, which is the only
    /// part that says which field to fix.
    private static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return "\(error)" }

        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }

        switch error {
        case let .typeMismatch(type, context):
            return "type mismatch at '\(path(context))': expected \(type). \(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "null at '\(path(context))' for non-optional \(type). \(context.debugDescription)"
        case let .keyNotFound(key, context):
            let prefix = path(context)
            return "missing key '\(prefix.isEmpty ? key.stringValue : "\(prefix).\(key.stringValue)")'. "
                + context.debugDescription
        case let .dataCorrupted(context):
            return "corrupted at '\(path(context))'. \(context.debugDescription)"
        @unknown default:
            return "\(error)"
        }
    }
}
