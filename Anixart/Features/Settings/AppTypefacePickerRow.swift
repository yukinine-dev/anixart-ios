import SwiftUI

/// Insert this row into the device appearance Form. No account/API writes are made.
@MainActor
struct AppTypefacePickerRow: View {
    @State private var preferences: AppTypefacePreferences

    init(preferences: AppTypefacePreferences = .shared) {
        _preferences = State(initialValue: preferences)
    }

    var body: some View {
        Picker("Шрифт", selection: Binding(
            get: { preferences.typeface },
            set: { preferences.setTypeface($0) }
        )) {
            ForEach(AppTypeface.allCases) { typeface in
                Text(typeface.title).tag(typeface)
            }
        }
        .accessibilityIdentifier("appearance.typeface")
        .accessibilityValue(preferences.typeface.title)
        .onAppear { preferences.reload() }
    }
}
