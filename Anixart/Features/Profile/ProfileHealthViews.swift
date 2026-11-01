import SwiftUI
import AnixartKit

@MainActor
struct ProfileHealthView: View {
    @Environment(AppEnvironment.self) private var env
    let account: ProfileAccountKey?
    var channelID: Int?
    @State private var resource = ProfileResource<ProfileHealthStatusResponse>()
    @State private var kind: ProfileEnforcementListView.Kind = .account
    @State private var lists: [ProfileEnforcementListView.Kind: Paginator<ProfileEnforcement>] = [:]
    @State private var showsHelp = false

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account, let health = resource.value {
                Section {
                    Button { showsHelp = true } label: {
                        Label(health.banCount == 0 && env.session.profile?.isBanned != true && !isFuture(health.lastBanExpires)
                              && !isFuture(health.blogSuspensionExpires) && !isFuture(health.blogMuteExpires)
                              ? "Вы безупречны" : "История ограничений аккаунта", systemImage: "checkmark.shield")
                            .font(.ax(.title3, .medium)).padding(.vertical, 12)
                    }.buttonStyle(.plain)
                    Button("Что это значит?") { showsHelp = true }
                }
                Section("Ограничения") {
                    restriction("Аккаунт", expires: health.lastBanExpires,
                                isActive: env.session.profile?.isBanned == true || isFuture(health.lastBanExpires))
                    restriction("Публикация в блоге", expires: health.blogSuspensionExpires, isActive: isFuture(health.blogSuspensionExpires))
                    restriction("Видимость блога", expires: health.blogMuteExpires, isActive: isFuture(health.blogMuteExpires))
                }
                Section("История блокировок") {
                    LabeledContent("Всего", value: Format.count(health.banCount))
                    LabeledContent("За последние 3 месяца", value: Format.count(health.banFor3MonthCount))
                    if let timestamp = health.lastBanTimestamp, timestamp > 0 {
                        LabeledContent("Последняя блокировка", value: ProfileDate.text(timestamp))
                    }
                }
                Section {
                    Picker("История", selection: $kind) {
                        Text("Ограничения").tag(ProfileEnforcementListView.Kind.account)
                        Text("Действия с контентом").tag(ProfileEnforcementListView.Kind.content)
                    }.pickerStyle(.segmented)
                    if let list = lists[kind] {
                        PaginatedContent(paginator: list, emptyTitle: "Нет данных для отображения") { enforcement in
                            NavigationLink {
                                ProfileEnforcementDetailView(enforcementID: enforcement.id, preloaded: enforcement,
                                                             account: account, channelID: channelID)
                            } label: { ProfileEnforcementRow(enforcement: enforcement) }
                        }
                    }
                }
                ProfileSaveError(message: resource.errorMessage)
            } else if account != nil, env.session.accountKey == account {
                ProfileResourceState(resource: resource, title: "Не удалось загрузить здоровье аккаунта", retry: load)
            }
        }
        .font(.ax(.body))
        .navigationTitle("Здоровье аккаунта")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await load(); await lists[kind]?.reload() }
        .task(id: kind) { if resource.value == nil { await load() }; await loadList() }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { resource.reset(); lists = [:]; showsHelp = false }
        }
        .sheet(isPresented: $showsHelp) {
            ProfileHelpSheet(title: "Здоровье аккаунта", paragraphs: [
                "Здесь отображается история нарушений, ограничений аккаунта и действий модераторов с вашим контентом.",
                "Сроки и причины ограничений указаны в деталях нарушения. Если апелляция доступна, её можно подать из этих деталей."
            ])
        }
    }

    private func isFuture(_ timestamp: Int?) -> Bool {
        (timestamp ?? 0) > Int(Date.now.timeIntervalSince1970)
    }

    private func restriction(_ title: String, expires: Int?, isActive: Bool) -> some View {
        HStack(alignment: .top) {
            Image(systemName: isActive ? "exclamationmark.shield" : "checkmark.shield")
                .foregroundStyle(isActive ? Color.orange : Theme.listColor(.watching))
            ProfileEditorRow(title: title, subtitle: isActive
                ? ((expires ?? 0) > 0 ? "Ограничено до \(ProfileDate.dateTime(expires))" : "Ограничено бессрочно")
                : "Нет действующих ограничений")
        }
    }

    private func load() async {
        guard let account else { return }
        await resource.load { try await env.session.sendAccountRequest(ProfileSecurityEndpoints.health(), for: account) }
    }

    private func loadList() async {
        guard let account, env.session.accountKey == account else { return }
        let kind = self.kind
        if lists[kind] == nil {
            let session = env.session
            lists[kind] = Paginator(continuesWithoutPageCount: true) { page in
                let items = try await session.sendAccountRequest(ProfileSecurityEndpoints.enforcements(account: kind == .account, page: page), for: account)
                return PageableResponse(content: items, currentPage: page)
            }
        }
        await lists[kind]?.loadFirstPageIfNeeded()
    }
}

@MainActor
struct ProfileEnforcementListView: View {
    enum Kind: Hashable, Sendable { case account, content }
    @Environment(AppEnvironment.self) private var env
    let kind: Kind
    let account: ProfileAccountKey?
    var channelID: Int?
    @State private var paginator: Paginator<ProfileEnforcement>?

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Нарушений нет") { enforcement in
                    NavigationLink {
                        ProfileEnforcementDetailView(enforcementID: enforcement.id, preloaded: enforcement,
                                                     account: account, channelID: channelID)
                    } label: { ProfileEnforcementRow(enforcement: enforcement) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(kind == .account ? "Нарушения аккаунта" : "Нарушения контента")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .task {
            guard let account else { return }
            if paginator == nil {
                let session = env.session
                let isAccount = kind == .account
                paginator = Paginator(continuesWithoutPageCount: true) { page in
                    let items = try await session.sendAccountRequest(
                        ProfileSecurityEndpoints.enforcements(account: isAccount, page: page), for: account
                    )
                    // This API returns no paging metadata; an empty array is its
                    // only end marker. Do not invent a page size.
                    return PageableResponse(content: items, currentPage: page)
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { paginator = nil }
        }
    }
}

struct ProfileEnforcementRow: View {
    let enforcement: ProfileEnforcement
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(enforcement.title).font(.ax(.headline)).foregroundStyle(.primary)
            if let reason = enforcement.reason, !reason.isEmpty {
                Text(reason).font(.ax(.subheadline)).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack {
                Text(ProfileDate.text(enforcement.creationTimestamp))
                Spacer()
                if enforcement.isRevoked == true { Text("Отменено").foregroundStyle(Theme.listColor(.watching)) }
                else if enforcement.isExpired() { Text("Срок истёк") }
            }
            .font(.ax(.caption)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}

@MainActor
struct ProfileEnforcementDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let enforcementID: Int
    var preloaded: ProfileEnforcement?
    let account: ProfileAccountKey?
    var channelID: Int?
    @State private var resource = ProfileResource<ProfileEnforcementResponse>()

    private var enforcement: ProfileEnforcement? {
        resource.value?.enforcement ?? (preloaded?.id == enforcementID ? preloaded : nil)
    }

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account, let enforcement, enforcement.hasValidDetails {
                Section {
                    Text(enforcement.title).font(.ax(.title3, .medium))
                    if let reason = enforcement.reason { Text(reason).font(.ax(.body)).textSelection(.enabled) }
                    LabeledContent("Дата", value: ProfileDate.dateTime(enforcement.creationTimestamp))
                    if let expires = enforcement.expirationTimestamp {
                        LabeledContent("Срок", value: expires > 0 ? ProfileDate.dateTime(expires) : "Бессрочно")
                    }
                    if enforcement.isRevoked == true {
                        Label("Ограничение отменено", systemImage: "checkmark.shield").foregroundStyle(Theme.listColor(.watching))
                        if let timestamp = enforcement.revocationTimestamp {
                            LabeledContent("Дата отмены", value: ProfileDate.dateTime(timestamp))
                        }
                    } else if enforcement.isExpired() { Text("Срок ограничения истёк").foregroundStyle(.secondary) }
                }
                if let changes = enforcement.changes, !changes.isEmpty {
                    Section("Изменения модератора") {
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, change in Text(change.title) }
                    }
                }
                contentLink(enforcement)
                Section("Апелляция") {
                    LabeledContent("Статус", value: enforcement.appealStatusTitle)
                    if let timestamp = enforcement.appealSubmitTimestamp, timestamp > 0 {
                        LabeledContent("Подана", value: ProfileDate.dateTime(timestamp))
                    }
                    if let timestamp = enforcement.appealProcessTimestamp, timestamp > 0 {
                        LabeledContent("Рассмотрена", value: ProfileDate.dateTime(timestamp))
                    }
                    if let message = enforcement.appealProcessMessage, !message.isEmpty {
                        Text(message).font(.ax(.body)).textSelection(.enabled)
                    }
                    if enforcement.appealRoute == .messageForm, enforcement.mayAppeal() {
                        NavigationLink {
                            ProfileEnforcementAppealView(enforcementID: enforcementID, account: account)
                        } label: { Label("Подать апелляцию", systemImage: "envelope") }
                        .disabled(resource.value?.enforcement == nil || env.session.accountKey != account)
                        Text("Доступна до \(ProfileDate.dateTime(enforcement.appealExpiresTimestamp))")
                            .font(.ax(.caption)).foregroundStyle(.secondary)
                    } else if enforcement.appealRoute == .enforcementDetails {
                        Text("Апелляция этого типа связана с корректировкой контента. Проверьте сведения об изменении выше.")
                            .font(.ax(.subheadline)).foregroundStyle(.secondary)
                    } else if enforcement.appealRoute == .result {
                        NavigationLink("Результат апелляции") { ProfileEnforcementAppealResultView(enforcement: enforcement, account: account) }
                    } else if enforcement.appealStatus?.matches(name: "NOT_SUBMITTED", ordinal: 1) == true {
                        Text("Подача апелляции недоступна или срок подачи истёк.").foregroundStyle(.secondary)
                    }
                }
                if let error = resource.errorMessage {
                    StatusMessageView(title: "Не удалось обновить нарушение", message: error, retry: load)
                }
            } else if account != nil, env.session.accountKey == account, let enforcement, !enforcement.hasValidDetails {
                StatusMessageView(title: "Данные нарушения недоступны", message: "Сервер не вернул поддерживаемые сведения об этом нарушении.")
            } else if account != nil, env.session.accountKey == account {
                ProfileResourceState(resource: resource, title: "Не удалось загрузить нарушение", retry: load)
            }
        }
        .font(.ax(.body))
        .navigationTitle("Нарушение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { resource.reset() }
        }
    }

    @ViewBuilder
    private func contentLink(_ enforcement: ProfileEnforcement) -> some View {
        if let id = enforcement.contentID {
            Section("Затронутый контент") {
                if enforcement.type == "collection_edit" {
                    NavigationLink { ProfileCollectionDestination(collectionID: id, preloaded: collection(enforcement), viewer: account?.viewerKey) } label: {
                        Text(collection(enforcement)?.displayTitle ?? "Открыть коллекцию")
                    }
                } else if enforcement.type == "article_edit" {
                    NavigationLink { ProfileArticleView(articleID: id, preloaded: article(enforcement), viewer: account?.viewerKey) } label: { Text("Открыть запись") }
                } else if let category = enforcement.commentCategory {
                    if let comment = comment(enforcement) {
                        Text(comment.message ?? "Комментарий").font(.ax(.subheadline)).textSelection(.enabled)
                    }
                    NavigationLink {
                        ProfileCommentDetailView(commentID: id, category: category, preloaded: comment(enforcement),
                                                 viewer: account?.viewerKey)
                    } label: { Text("Открыть комментарий") }
                } else if ["channel_mute", "channel_suspension"].contains(enforcement.type) {
                    NavigationLink("Открыть канал") { ProfileChannelView(channelID: id, viewer: account?.viewerKey) }
                }
            }
        } else if ["channel_mute", "channel_suspension"].contains(enforcement.type), let channelID {
            Section {
                NavigationLink("Открыть канал") { ProfileChannelView(channelID: channelID, viewer: account?.viewerKey) }
            }
        }
    }

    private func collection(_ enforcement: ProfileEnforcement) -> ReleaseCollection? {
        if case .collection(let value)? = enforcement.entity { return value.value }
        return nil
    }

    private func article(_ enforcement: ProfileEnforcement) -> Article? {
        if case .article(let value)? = enforcement.entity { return value.value }
        return nil
    }

    private func comment(_ enforcement: ProfileEnforcement) -> ProfileComment? {
        if case .comment(let value)? = enforcement.entity { return value.value }
        return nil
    }

    private func load() async {
        guard let account else { return }
        await resource.load {
            let response = try await env.session.sendAccountRequest(ProfileSecurityEndpoints.enforcement(id: enforcementID), for: account)
            guard response.enforcement?.id == enforcementID else {
                throw AnixartError.decoding(message: "Ответ не содержит нарушение", path: "profile/health/enforcement/\(enforcementID)")
            }
            return response
        }
    }
}

@MainActor
struct ProfileEnforcementAppealView: View {
    @Environment(AppEnvironment.self) private var env
    let enforcementID: Int
    let account: ProfileAccountKey?
    @State private var resource = ProfileResource<ProfileEnforcementResponse>()
    @State private var message = ""
    @State private var isSaving = false
    @State private var confirmsSubmit = false
    @State private var hasSubmitted = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        guard let enforcement = resource.value?.enforcement, enforcement.appealRoute == .messageForm, enforcement.mayAppeal(),
               account != nil, env.session.accountKey == account, !resource.isLoading,
               resource.errorMessage == nil, !isSaving, !hasSubmitted else { return false }
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account {
            if hasSubmitted {
                Section {
                    Label("Апелляция отправлена", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Text("Результат появится в деталях нарушения после рассмотрения.")
                }
            } else if let enforcement = resource.value?.enforcement {
                Section("Нарушение") {
                    Text(enforcement.title).font(.ax(.headline))
                    if let reason = enforcement.reason { Text(reason).font(.ax(.subheadline)).foregroundStyle(.secondary) }
                }
                if enforcement.appealRoute == .messageForm, enforcement.mayAppeal() {
                        Section("Сообщение модератору") {
                            TextField("Объясните, почему нарушение нужно пересмотреть", text: $message, axis: .vertical)
                                .lineLimit(5...12)
                        }
                    Section { Button("Отправить апелляцию") { confirmsSubmit = true }.disabled(!canSubmit) }
                } else if enforcement.appealRoute == .enforcementDetails {
                    Section {
                        NavigationLink("Детали изменения контента") {
                            ProfileEnforcementDetailView(enforcementID: enforcementID, preloaded: enforcement, account: account)
                        }
                    }
                } else if enforcement.appealRoute == .result {
                    Section { NavigationLink("Результат апелляции") { ProfileEnforcementAppealResultView(enforcement: enforcement, account: account) } }
                } else {
                    Section { Text("Подача апелляции больше недоступна. Статус: \(enforcement.appealStatusTitle).") }
                }
            } else { ProfileResourceState(resource: resource, title: "Не удалось загрузить апелляцию", retry: load) }
            ProfileSaveError(message: errorMessage ?? resource.errorMessage)
            }
        }
        .font(.ax(.body))
        .disabled(isSaving || account == nil || env.session.accountKey != account)
        .navigationTitle("Апелляция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
        .onChange(of: env.session.accountKey) { _, current in
            guard account != current else { return }
            resource.reset()
            message = ""
            confirmsSubmit = false
            hasSubmitted = false
            errorMessage = nil
        }
        .confirmationDialog("Отправить апелляцию?", isPresented: $confirmsSubmit, titleVisibility: .visible) {
            Button("Отправить") { Task { await submit() } }
        } message: { Text("Апелляция будет передана модератору на рассмотрение.") }
    }

    private func load() async {
        guard let account else { return }
        await resource.load {
            let response = try await env.session.sendAccountRequest(ProfileSecurityEndpoints.enforcement(id: enforcementID), for: account)
            guard response.enforcement?.id == enforcementID else {
                throw AnixartError.decoding(message: "Ответ не содержит нарушение", path: "profile/health/enforcement/\(enforcementID)")
            }
            return response
        }
    }

    private func submit() async {
        guard canSubmit, let account, let enforcement = resource.value?.enforcement else { return }
        let draft = message.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfileSecurityEndpoints.appeal(id: enforcementID, message: draft), for: account)
            hasSubmitted = true
            message = ""
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

struct ProfileEnforcementAppealResultView: View {
    @Environment(AppEnvironment.self) private var env
    let enforcement: ProfileEnforcement
    let account: ProfileAccountKey?
    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account {
                LabeledContent("Статус", value: enforcement.appealStatusTitle)
                if let message = enforcement.appealProcessMessage, !message.isEmpty {
                    Text(message).font(.ax(.body)).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Результат апелляции").navigationBarTitleDisplayMode(.inline)
    }
}
