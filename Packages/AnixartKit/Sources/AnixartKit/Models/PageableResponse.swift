import Foundation

/// Anixart's paging envelope (`com.swiftsoft.anixartd.network.response.PageableResponse`).
///
/// Requests are zero-based: `filter/0` is the first page. These fields preserve the
/// server's wire values. Some browsing endpoints use zero placeholders or a final
/// page index, not a number of pages; their callers need explicit raw-size paging.
public struct PageableResponse<Element: Codable & Sendable>: Codable, Sendable, AnixartResponse {
    public var code: Int?
    public var content: [Element]?
    public var currentPage: Int?
    public var totalCount: Int?
    public var totalPageCount: Int?

    public enum CodingKeys: String, CodingKey {
        case code
        case content
        case currentPage = "current_page"
        case totalCount = "total_count"
        case totalPageCount = "total_page_count"
    }

    public init(
        code: Int? = nil,
        content: [Element]? = nil,
        currentPage: Int? = nil,
        totalCount: Int? = nil,
        totalPageCount: Int? = nil
    ) {
        self.code = code
        self.content = content
        self.currentPage = currentPage
        self.totalCount = totalCount
        self.totalPageCount = totalPageCount
    }

    public var items: [Element] { content ?? [] }

    /// Legacy metadata-based next index, retained for existing callers. It is not
    /// suitable for endpoints with placeholder/final-index page counts.
    public var nextPage: Int? {
        let current = currentPage ?? 0
        let total = totalPageCount ?? 0
        return current + 1 < total ? current + 1 : nil
    }

    public var isLastPage: Bool { nextPage == nil }
}
