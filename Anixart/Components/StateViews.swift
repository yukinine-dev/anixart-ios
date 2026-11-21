import SwiftUI

/// Centred message with an optional retry, used for every empty and failed state
/// so they look the same everywhere.
@MainActor
struct StatusMessageView: View {
    let title: String
    var message: String?
    var systemImage: String = "tray"
    var retry: (() async -> Void)?
    @State private var showsInfo = false

    var body: some View {
        if let retry {
            failureBody(retry: retry)
        } else {
            plainBody
        }
    }

    /// Beta 3's failed-load state: «Ой, что-то не так…», a light «Повторить» pill and a
    /// quiet «Узнать подробнее» link that opens the connection help. The specific cause,
    /// when there is one, stays below as small text.
    private func failureBody(retry: @escaping () async -> Void) -> some View {
        VStack(spacing: 12) {
            Text("Ой, что-то не так…").font(.ax(.title2, .semibold))
            Text("Произошла ошибка при загрузке")
                .font(.ax(.title3)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let message, !message.isEmpty {
                Text(message).font(.ax(.caption)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            Button {
                Task { await retry() }
            } label: {
                Text("Повторить")
                    .font(.ax(.title3, .medium))
                    .foregroundStyle(Color.black)
                    .frame(width: 240)
                    .padding(.vertical, 14)
                    .background(Color(white: 0.88), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            Button("Узнать подробнее") { showsInfo = true }
                .font(.ax(.title3)).foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showsInfo) { ConnectionInfoSheet() }
    }

    private var plainBody: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.ax(.headline))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// «Информация»: what the Android beta shows behind «Узнать подробнее» on a failed load.
/// Copied from a screen capture of beta 3. The yellow «Сейчас проводятся технические
/// работы» and red «Проблемы в работе приложения» cards appear there only when the
/// server reports maintenance; where that comes from is not in the decompiled code, so
/// they are not reproduced. Items 3 (reinstall from the site) and 4 (Google Play) and the
/// «Альтернативное соединение» option have no iOS equivalent and are reworded or left out.
@MainActor
struct ConnectionInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsUkraine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Информация").font(.ax(.largeTitle)).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Общие рекомендации").font(.ax(.title3, .semibold))
                    Text("1. Проверьте стабильность интернет-соединения. Возможно, возникли неполадки у вашего интернет-провайдера.")
                    Text(socialLine)
                    Text("3. Попробуйте перезагрузить устройство или переустановить приложение.")
                    Text("4. Воспользуйтесь VPN.")

                    DisclosureGroup(isExpanded: $showsUkraine) {
                        Text("Доступ к приложению ограничивается интернет-провайдерами на территории Украины. Если вы испытываете проблемы, воспользуйтесь VPN.")
                            .padding(.top, 8)
                    } label: {
                        Text("Информация о доступности в Украине").font(.ax(.title3))
                    }
                    .padding(16)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.3)))
                    .padding(.top, 8)
                }
                .font(.ax(.title3))
                .tint(Theme.accent)
            }
            HStack {
                Spacer()
                Button("Закрыть") { dismiss() }.font(.ax(.title3, .medium)).padding(.top, 12)
            }
        }
        .padding(24)
        .presentationDetents([.large])
    }

    private var socialLine: AttributedString {
        var text = AttributedString("2. Возможно, возникли неполадки с нашей стороны или проводятся технические работы. Проверьте информацию в наших социальных сетях ")
        var telegram = AttributedString("Telegram")
        telegram.link = URL(string: "https://t.me/anixart_app")
        telegram.underlineStyle = .single
        var vk = AttributedString("ВКонтакте")
        vk.link = URL(string: "https://vk.com/anixart_app")
        vk.underlineStyle = .single
        text += telegram + AttributedString(" и ") + vk
        return text
    }
}

/// Renders the states of a `Paginator` in the right order: first-page spinner,
/// then failure, then empty, then content.
@MainActor
struct PaginatedContent<Item: Identifiable & Codable & Sendable, Row: View>: View {
    let paginator: Paginator<Item>
    var emptyTitle: String = "Пока ничего нет"
    var emptyMessage: String?
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        if paginator.isLoadingFirstPage || (!paginator.hasLoaded && paginator.errorMessage == nil) {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if let error = paginator.errorMessage, paginator.items.isEmpty {
            StatusMessageView(
                title: "Не удалось загрузить",
                message: error,
                systemImage: "wifi.exclamationmark",
                retry: { await paginator.retry() }
            )
        } else if paginator.items.isEmpty {
            StatusMessageView(title: emptyTitle, message: emptyMessage)
        } else {
            ForEach(paginator.items) { item in
                row(item)
                    .onAppear {
                        if item.id == paginator.items.last?.id {
                            Task { await paginator.loadNextPage() }
                        }
                    }
            }
            if paginator.state == .loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if let error = paginator.errorMessage {
                StatusMessageView(title: paginator.failedPage == 0 ? "Не удалось обновить список" : "Не удалось загрузить следующую страницу", message: error,
                                  systemImage: "wifi.exclamationmark", retry: { await paginator.retry() })
            }
        }
    }
}

/// Horizontal carousel with a heading and an optional "see all" destination.
@MainActor
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.ax(.title3, .semibold))
            Spacer()
            trailing
        }
        .padding(.horizontal)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
