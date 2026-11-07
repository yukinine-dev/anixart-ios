import SwiftUI
import AnixartKit

@MainActor
struct FeedView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: FeedViewModel?
    @State private var selection: FeedTab = .my
    @State private var path: [FeedRouteContext] = []
    @State private var showsSearch = false
    @State private var showsSettings = false
    @State private var onlySubscribedManaged = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false
    @Namespace private var tabIndicator
    @State private var selectionMotion = SelectionMotionIntent<FeedTab>()
    private var motion: AppMotionPolicy { AppMotionPolicy(reduceMotion: reduceMotion, resourceSaving: resourceSaving) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                BrowsingHeader(onSettings: { showsSettings = true }, onSearch: { showsSearch = true })
                tabs.floatingStrip()
                Group {
                    if let model, model.hasCurrentViewer {
                        if model.viewer.account == nil {
                            SignInPromptView(message: "Войдите, чтобы читать свою ленту и свежие записи. Поиск записей, блогов и каналов доступен без входа.")
                        } else {
                            content(model)
                        }
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                .transaction {
                    if selectionMotion.shouldAnimate(selection) {
                        $0.animation = nil; $0.disablesAnimations = true
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: FeedRouteContext.self) { context in
                if let model { FeedDestinationView(context: context, actions: model.actions) }
            }
            .navigationDestination(isPresented: $showsSearch) {
                if let model { FeedSearchView(viewer: model.viewer, actions: model.actions) }
            }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .task(id: env.session.viewerKey) {
                if model?.viewer != env.session.viewerKey {
                    model = FeedViewModel(session: env.session)
                    if selection == .managed, !env.session.isSignedIn { selection = .my }
                    onlySubscribedManaged = true
                }
            }
            .task(id: loadKey) { await model?.load(selection) }
            .onChange(of: model?.actions.membershipRevision) { _, revision in
                if let revision, revision > 0 { Task { await model?.rebaseAfterMembershipChange() } }
            }
            .onChange(of: env.session.viewerKey) { _, _ in path = []; showsSearch = false; selectionMotion.reset() }
        }
    }

    private var loadKey: FeedLoadKey { FeedLoadKey(viewer: model?.viewer, tab: selection, onlySubscribed: onlySubscribedManaged) }

    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.tabGap) {
                    ForEach(FeedTab.visibleTabs(signedIn: env.session.isSignedIn)) { tab in
                        Button { select(tab) } label: {
                            VStack(spacing: 8) {
                                if tab == .managed { Image(systemName: "star.circle").font(.ax(.title3)) }
                                else { SelectionLabel(title: tab.title, isSelected: selection == tab) }
                                SelectionUnderline(isSelected: selection == tab, namespace: tabIndicator)
                            }
                            .foregroundStyle(selection == tab ? Theme.selection : Color.secondary)
                            .fixedSize().padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onKeyPress(.return) { select(tab, fromKeyboard: true); return .handled }
                        .onKeyPress(.space) { select(tab, fromKeyboard: true); return .handled }
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                        .id(tab)
                    }
                }.padding(.horizontal, 16)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, tab in
                guard tab == selection else { return }
                motion.perform(animated: selectionMotion.shouldAnimate(tab)) { proxy.scrollTo(tab, anchor: .center) }
                selectionMotion.complete(tab)
            }
        }
    }

    private func select(_ tab: FeedTab, fromKeyboard: Bool = false) {
        guard selection != tab else { return }
        selectionMotion.register(tab, fromKeyboard: fromKeyboard)
        motion.perform(animated: !fromKeyboard) { selection = tab }
    }

    @ViewBuilder
    private func content(_ model: FeedViewModel) -> some View {
        switch selection {
        case .my:
            FeedTimelineView(model: model.my, actions: model.actions, isActive: selection == .my) {
                myHeader(model)
            }
        case .fresh:
            FeedTimelineView(model: model.fresh, actions: model.actions, isActive: selection == .fresh) { EmptyView() }
        case .managed:
            VStack(spacing: 0) {
                HStack {
                    Text("Управляемые").font(.ax(.headline))
                    Spacer()
                    Picker("Фильтр", selection: Binding(get: { onlySubscribedManaged }, set: { value in
                        onlySubscribedManaged = value
                        model.setManagedFilter(onlySubscribed: value)
                    })) {
                        Text("Все каналы").tag(false)
                        Text("Только с подпиской").tag(true)
                    }.pickerStyle(.menu)
                }.padding(.horizontal).padding(.vertical, 8)
                FeedChannelListContent(model: model.managed, actions: model.actions, observesMembershipChanges: false)
            }
        }
    }

    private func myHeader(_ model: FeedViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NavigationLink(value: FeedRouteContext(route: .subscriptions, viewer: model.viewer)) {
                    Label("Мои подписки", systemImage: "person.2")
                }.buttonStyle(.plain)
                Spacer()
                FeedDateFilterButton(model: model.my)
            }.font(.ax(.subheadline)).padding(.horizontal)
            if model.subscriptions.paginator.items.isEmpty, let error = model.subscriptions.paginator.errorMessage {
                StatusMessageView(title: "Не удалось загрузить подписки", message: error, retry: { await model.subscriptions.reload() })
            } else if !model.subscriptions.paginator.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        Button { model.my.apply(filter: FeedFilter(date: model.my.filter.date)) } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "rectangle.stack").frame(width: 52, height: 52).background(.quaternary, in: Circle())
                                Text("Все").font(.ax(.caption))
                            }.frame(width: 76).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        ForEach(model.subscriptions.paginator.items) { channel in
                            Button { model.my.apply(filter: FeedFilter(channelID: channel.id, date: model.my.filter.date)) } label: {
                                VStack(spacing: 6) {
                                    Avatar(url: AnixartURL.image(channel.avatar), size: 52)
                                        .overlay { Circle().strokeBorder(model.my.filter.channelID == channel.id ? Color.primary : .clear, lineWidth: 2) }
                                    Text(channel.title ?? "Канал").font(.ax(.caption)).lineLimit(1)
                                }.frame(width: 76).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal)
                }
            }
            if model.subscriptionCount.value?.subscriptionCount == 0, model.subscriptionCount.errorMessage == nil,
               model.subscriptions.paginator.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ой, а подписок-то нет!").font(.ax(.headline))
                    Text("Но ничего страшного, Вы можете подписаться на популярные каналы из списка ниже")
                        .font(.ax(.subheadline)).foregroundStyle(.secondary)
                }.padding(.horizontal)
                FeedChannelCarousel(channels: model.recommendations.paginator.items, viewer: model.viewer, actions: model.actions)
                if let error = model.recommendations.paginator.errorMessage {
                    StatusMessageView(title: "Не удалось загрузить каналы", message: error, retry: { await model.recommendations.reload() })
                }
            }
        }.padding(.vertical, 12)
    }
}

@MainActor
struct FeedTimelineView<Header: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    let model: FeedTimelineModel
    let actions: FeedActionsModel
    let isActive: Bool
    @ViewBuilder var header: Header

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if model.hasNewArticles {
                    Button("Новые записи") { Task { await model.reload() } }
                        .font(.ax(.subheadline, .medium)).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                if let error = actions.errorMessage {
                    Text(error).font(.ax(.subheadline)).foregroundStyle(.red).padding(.horizontal)
                }
                PaginatedContent(paginator: model.paginator, emptyTitle: "Похоже, нет ни одной записи") { article in
                    FeedArticleRow(source: article, actions: actions)
                }
                if let error = model.updateError {
                    StatusMessageView(title: "Не удалось проверить новые записи", message: error, retry: { await model.checkForUpdates() })
                }
            }
        }
        .refreshable { await model.reload() }
        .task(id: ObjectIdentifier(model.paginator)) { if model.hasCurrentViewer { await model.paginator.loadFirstPageIfNeeded() } }
        .task(id: "\(isActive)-\(scenePhase == .active)") {
            guard isActive, scenePhase == .active, model.kind == .fresh else { return }
            while !Task.isCancelled, model.hasCurrentViewer {
                do { try await Task.sleep(for: .seconds(120)) } catch { return }
                await model.checkForUpdates()
            }
        }
    }
}

private struct FeedLoadKey: Equatable {
    let viewer: ProfileViewerKey?
    let tab: FeedTab
    let onlySubscribed: Bool
}

@MainActor
private struct FeedDateFilterButton: View {
    let model: FeedTimelineModel

    var body: some View {
        Menu {
            Picker("Период", selection: Binding(get: { model.filter.period }, set: { period in
                model.apply(filter: FeedFilter(channelID: model.filter.channelID, date: period.rawValue))
            })) {
                ForEach(FeedDatePeriod.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Label(model.filter.period.title, systemImage: "calendar")
        }
        .buttonStyle(.plain)
    }
}
