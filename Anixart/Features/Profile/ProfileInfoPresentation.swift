import Foundation
import SwiftUI

/// Shared by the identity controls: only one reputation/contact presentation can
/// belong to this profile at a time. Its ID also scopes late dismissal callbacks.
struct ProfileInfoPresentation: Identifiable, Equatable {
    enum Source: Equatable, Sendable { case reputation, contacts }
    enum Kind: Equatable, Sendable { case popover, sheet }

    let id = UUID()
    let source: Source
    let kind: Kind
}

enum ProfileInfoPresentationPolicy {
    static func kind(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?,
                     dynamicType: DynamicTypeSize) -> ProfileInfoPresentation.Kind {
        guard horizontal == .regular, vertical == .regular, dynamicType < .xxLarge else { return .sheet }
        return .popover
    }

    static func sheetDetents(vertical: UserInterfaceSizeClass?, dynamicType: DynamicTypeSize) -> Set<PresentationDetent> {
        vertical == .compact || dynamicType >= .xxLarge ? [.large] : [.medium, .large]
    }
}

@MainActor
func profileInfoPresentationBinding(_ presentation: Binding<ProfileInfoPresentation?>,
                                    source: ProfileInfoPresentation.Source,
                                    kind: ProfileInfoPresentation.Kind) -> Binding<ProfileInfoPresentation?> {
    let expectedID = presentation.wrappedValue?.id
    return Binding(get: {
        guard let current = presentation.wrappedValue, current.id == expectedID,
              current.source == source, current.kind == kind else { return nil }
        return current
    }, set: { value in
        guard value == nil, let current = presentation.wrappedValue, current.id == expectedID,
              current.source == source, current.kind == kind else { return }
        presentation.wrappedValue = nil
    })
}

@MainActor
func dismissProfileInfoPresentation(_ presentation: Binding<ProfileInfoPresentation?>,
                                    ifCurrent expected: ProfileInfoPresentation) {
    guard presentation.wrappedValue?.id == expected.id else { return }
    presentation.wrappedValue = nil
}

@MainActor
private struct ProfileInfoPresentationModifier<Info: View>: ViewModifier {
    @Binding var presentation: ProfileInfoPresentation?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let source: ProfileInfoPresentation.Source
    let title: String
    let width: CGFloat
    let info: () -> Info

    init(presentation: Binding<ProfileInfoPresentation?>, source: ProfileInfoPresentation.Source,
         title: String, width: CGFloat, info: @escaping () -> Info) {
        _presentation = presentation
        self.source = source
        self.title = title
        self.width = width
        self.info = info
    }

    func body(content: Content) -> some View {
        content
            .popover(item: profileInfoPresentationBinding($presentation, source: source, kind: .popover),
                     attachmentAnchor: .rect(.bounds), arrowEdge: .top) { item in
                // A resized regular window can become compact while this is open;
                // let SwiftUI adapt this same presentation rather than opening two.
                ViewThatFits(in: .vertical) {
                    popoverContent(item).fixedSize(horizontal: false, vertical: true)
                    ScrollView { popoverContent(item) }
                }
                .frame(width: width)
                .frame(maxHeight: 360)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents(ProfileInfoPresentationPolicy.sheetDetents(
                    vertical: verticalSizeClass, dynamicType: dynamicTypeSize))
            }
            .sheet(item: profileInfoPresentationBinding($presentation, source: source, kind: .sheet)) { item in
                NavigationStack {
                    ScrollView {
                        info()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                            .frame(maxWidth: 600)
                            .frame(maxWidth: .infinity)
                    }
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Закрыть") { dismissProfileInfoPresentation($presentation, ifCurrent: item) }
                        }
                    }
                }
                .presentationDetents(ProfileInfoPresentationPolicy.sheetDetents(
                    vertical: verticalSizeClass, dynamicType: dynamicTypeSize))
                .presentationDragIndicator(.visible)
            }
    }

    private func popoverContent(_ item: ProfileInfoPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(title).font(.ax(.headline)).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { dismissProfileInfoPresentation($presentation, ifCurrent: item) } label: {
                    Image(systemName: "xmark").font(.ax(.subheadline))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Закрыть")
            }
            info()
        }
        .padding(16)
    }
}

extension View {
    @MainActor
    func profileInfoPresentation<Info: View>(_ presentation: Binding<ProfileInfoPresentation?>,
                                           source: ProfileInfoPresentation.Source, title: String, width: CGFloat = 300,
                                           @ViewBuilder info: @escaping () -> Info) -> some View {
        modifier(ProfileInfoPresentationModifier(presentation: presentation, source: source,
                                                title: title, width: width, info: info))
    }
}
