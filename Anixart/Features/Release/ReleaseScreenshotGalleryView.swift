import SwiftUI

/// Native paging and explicit controls; no custom zoom/dismiss animation or
/// image-sized transition. Reduce Motion uses a stationary page with the same
/// buttons and VoiceOver adjustment instead of a spatial paging transition.
@MainActor
struct ReleaseScreenshotGalleryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let presentation: ReleaseScreenshotPresentation
    @State private var model: ReleaseScreenshotGalleryModel?

    var body: some View {
        GeometryReader { geometry in
            let scale = displayScale.isFinite ? max(1, displayScale) : 1
            let edge = max(geometry.size.width, geometry.size.height)
            let pixels = edge.isFinite ? min(2048, max(1, edge * scale)) : 1200
            Group {
                if presentation.viewer == env.session.viewerKey, let model, !model.isInvalidated {
                    if model.urls.isEmpty {
                        Text("Кадров нет").font(.ax(.subheadline))
                    } else if reduceMotion {
                        page(model.selectedIndex, model: model)
                    } else {
                        TabView(selection: Binding(get: { model.selectedIndex }, set: { model.select($0) })) {
                            ForEach(model.urls.indices, id: \.self) { index in
                                page(index, model: model).tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                } else { ProgressView().tint(.white) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAdjustableAction { direction in
                guard let model else { return }
                switch direction {
                case .increment: model.select(model.selectedIndex + 1)
                case .decrement: model.select(model.selectedIndex - 1)
                @unknown default: break
                }
            }
            .task(id: GalleryLoadKey(pixels: Int(pixels.rounded(.up)), active: scenePhase == .active, viewer: env.session.viewerKey)) {
                if model == nil {
                    model = ReleaseScreenshotGalleryModel(urls: presentation.urls, initialIndex: presentation.initialIndex,
                                                          viewer: presentation.viewer, session: env.session)
                }
                if scenePhase == .active { await model?.loadVisibleImages(pixelSize: pixels) }
                else { model?.suspend() }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { controls }
        .onDisappear { model?.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model?.suspend() } }
        .onChange(of: env.session.viewerKey) { _, current in
            if presentation.viewer != current { model?.invalidate(); dismiss() }
        }
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
    }

    private var header: some View {
        HStack {
            Text("Кадры").font(.ax(.headline))
            Spacer()
            Button { model?.invalidate(); dismiss() } label: {
                Image(systemName: "xmark").font(.ax(.headline)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Закрыть кадры")
        }
        .padding(.horizontal)
        .background(.black.opacity(0.8))
    }

    private var controls: some View {
        HStack(spacing: 24) {
            Button { if let model { model.select(model.selectedIndex - 1) } } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Предыдущий кадр").disabled(model?.canGoBack != true)
            Text(model?.positionText ?? "")
                .font(.ax(.subheadline, .medium)).monospacedDigit()
                .accessibilityLabel("Кадр \(presentation.urls.isEmpty ? 0 : (model?.selectedIndex ?? 0) + 1) из \(presentation.urls.count)")
            Button { if let model { model.select(model.selectedIndex + 1) } } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Следующий кадр").disabled(model?.canGoForward != true)
        }
        .font(.ax(.headline))
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.8))
    }

    @ViewBuilder
    private func page(_ index: Int, model: ReleaseScreenshotGalleryModel) -> some View {
        Group {
            if let image = model.images[index] {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("Кадр \(index + 1) из \(model.urls.count)")
            } else if case .some(.failed(let problem)) = model.pageStates[index] {
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.exclamationmark").font(.ax(.largeTitle))
                    Text(problem.message).font(.ax(.subheadline)).multilineTextAlignment(.center)
                    if problem == .loadFailed {
                        Button("Попробовать ещё раз") { Task { await model.retry(index) } }
                            .font(.ax(.headline)).buttonStyle(.bordered)
                    }
                }
                .padding()
            } else if model.residentIndices.contains(index) {
                ProgressView().tint(.white).accessibilityLabel("Загрузка кадра \(index + 1)")
            } else { Color.clear }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GalleryLoadKey: Equatable {
    let pixels: Int
    let active: Bool
    let viewer: ProfileViewerKey
}
