import SwiftUI

struct ProfileGalleryPresentation: Identifiable {
    let id = UUID()
    let urls: [URL]
    let initialIndex: Int
}

/// The verified gallery contract is paging + a count + tappable controls. Pinch
/// and saving were not audited, so this does not invent a download/save flow.
@MainActor
struct ProfileImageGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    @State private var index: Int
    @State private var controlsVisible = true

    init(urls: [URL], initialIndex: Int = 0) {
        self.urls = urls
        _index = State(initialValue: max(0, min(initialIndex, urls.count - 1)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { offset, url in
                    CachedAsyncImage(url: url, maxPixelSize: 1600) { $0.resizable().scaledToFit() } placeholder: {
                        ProgressView().tint(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { controlsVisible.toggle() }
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            if controlsVisible {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Закрыть изображение")
                    Spacer()
                    Text("\(index + 1) из \(urls.count)").font(.ax(.headline)).monospacedDigit()
                    Spacer()
                    if urls.indices.contains(index) {
                        ShareLink(item: urls[index]) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }
                    }
                }
                .foregroundStyle(.white).padding(.horizontal, 12).background(.black.opacity(0.65))
            }
        }
        .statusBarHidden(!controlsVisible)
    }
}
