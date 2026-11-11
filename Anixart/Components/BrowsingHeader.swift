import SwiftUI

/// Shared header of the main sections (Главная, Обзор, Закладки, Лента) in the new
/// Android beta: logo, settings, notifications and the viewer's avatar. Search is
/// the round button next to the tab bar, so the header carries no search field.
/// `onSearch` is only for sections whose search is not the catalogue search.
@MainActor
struct BrowsingHeader: View {
    let onSettings: () -> Void
    var onSearch: (() -> Void)?

    var body: some View {
        OverviewHeader(onSettings: onSettings, onSearch: onSearch)
    }
}
