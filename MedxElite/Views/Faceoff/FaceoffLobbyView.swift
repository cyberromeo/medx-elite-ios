import SwiftUI

// MARK: - Lobby state

/// The lobby's own data: this profile's finished games, and the actions. The open lobbies come
/// from `MedxLobbyWatcher.shared`, the one stream Home's invite card and the Library badge
/// already read, so opening this screen does not open a second one.
///
/// There are two people using this app, so there are no game codes — the join row is every open
/// lobby the other one dealt. Joining is a single tap, and it is also the readiness signal: the
/// host's Start button is dead until it writes a player row.
@MainActor
final class MedxFaceoffLobby: ObservableObject {
    @Published private(set) var history: [MedxDuelGame]?
    @Published var failure: String?
    @Published var busy: String?
    /// Whether the game server answers, once a transport has been resolved; `nil` before.
    @Published private(set) var remoteWorks: Bool?

    private let injected: MedxDuelTransport?
    private var live: MedxDuelTransport?

    init(transport: MedxDuelTransport? = nil) {
        self.injected = transport
    }

    /// Resolved on first use, never at init: this object is created with its view, and resolving
    /// a transport while the SDK sign-in is still in flight is what used to latch the poller for
    /// the rest of the session.
    private var transport: MedxDuelTransport {
        if let injected { return injected }
        if let live { return live }
        let made = MedxDuelTransportFactory.make()
        live = made
        return made
    }

    private var uid: String? { AuthService.shared.currentSession?.uid }

    /// Gated on a uid: a read that fires before auth resolves reports a permission error that is a
    /// race, not a rules problem.
    func start() {
        guard uid != nil else { return }
        remoteWorks = transport.remoteWorks
        MedxLobbyWatcher.shared.start()
        Task { await reloadHistory() }
    }

    func reloadHistory() async {
        guard let uid else { return }
        do {
            history = try await transport.listMyDuels(uid: uid)
            remoteWorks = transport.remoteWorks
        } catch {
            failure = "Your past faceoffs could not be read."
        }
    }

    /// Lobbies the *other* one dealt and nobody has joined, from the shared stream.
    var theirs: [MedxDuelGame] {
        MedxLobbyWatcher.shared.theirs
    }

    var mine: [MedxDuelGame] {
        MedxLobbyWatcher.shared.lobbies.filter { $0.hostUid == uid && MedxDuelRules.isOfferable($0) }
    }

    var played: [MedxDuelGame] {
        (history ?? []).filter { $0.status == .done && !$0.log.isEmpty }
    }

    /// The head-to-head, across every finished game either of them hosted.
    var record: (wins: [String: Int], draws: Int, total: Int) {
        var wins = Dictionary(uniqueKeysWithValues: Profile.allProfiles.map { ($0.uid, 0) })
        var draws = 0
        for game in played {
            let scores = MedxDuelRules.finalScores(log: game.log, uids: game.uids)
            if let won = MedxDuelRules.leader(scores: scores, uids: game.uids), wins[won] != nil {
                wins[won, default: 0] += 1
            } else {
                draws += 1
            }
        }
        return (wins, draws, played.count)
    }

    // MARK: - Actions

    func join(_ game: MedxDuelGame) async -> String? {
        guard let uid, let profile = AuthService.shared.currentProfile else { return nil }
        busy = game.id
        defer { busy = nil }
        do {
            try await transport.joinGame(gameId: game.id, uid: uid, profile: profile.id)
            return game.id
        } catch {
            failure = "Joining did not go through. Check your connection and try again."
            return nil
        }
    }

    func cancel(_ game: MedxDuelGame) async {
        busy = game.id
        defer { busy = nil }
        do {
            try await transport.abandonGame(gameId: game.id)
        } catch {
            failure = "That lobby would not close."
        }
    }

    /// Deal the deck and open the lobby.
    ///
    /// The questions are resolved and written out here rather than re-fetched on each side, because
    /// a custom module may only exist on this device and because the shuffle has to be the same for
    /// both of them — which is only guaranteed if it happens once.
    func deal(pick: MedxFaceoffPick, length: Int) async -> String? {
        guard let uid, let profile = AuthService.shared.currentProfile else { return nil }
        busy = "deal"
        failure = nil
        defer { busy = nil }

        let questions: [Question]
        let source: MedxDuelSource

        switch pick {
        case .custom(let module):
            let built = await MedxCustomModuleStore.shared.buildQuestions(for: module)
            questions = built.questions
            source = MedxDuelSource(kind: "custom", id: module.id, name: module.name, subject: "Custom")
        case .series(let paper):
            guard let token = try? await AuthService.shared.getValidIdToken(),
                  let fetched = try? await FirestoreService.shared.fetchTestQuestions(
                    testId: paper.id,
                    idToken: token
                  )
            else {
                failure = "That paper's questions could not be read."
                return nil
            }
            questions = fetched
            source = MedxDuelSource(kind: "series", id: paper.id, name: paper.title, subject: paper.title)
        }

        let dealt = MedxDuelRules.deal(questions: questions, length: length, shuffle: true)
        guard !dealt.deck.isEmpty else {
            failure = "Nothing in that source has an answer key, so there would be nothing to score."
            return nil
        }

        do {
            return try await transport.createGame(
                hostUid: uid,
                hostProfile: profile.id,
                source: source,
                deck: dealt.deck,
                parts: dealt.parts
            )
        } catch {
            failure = "That game could not be started. Check your connection and try again."
            return nil
        }
    }
}

/// What a host has picked to play.
enum MedxFaceoffPick: Hashable {
    case custom(MedxCustomModule)
    /// A Marrow series paper, keyed by its `medx_test_questions` id.
    case series(MedxSeriesPaper)

    var name: String {
        switch self {
        case .custom(let module): return module.name
        case .series(let paper): return paper.title
        }
    }

    /// The most questions this source could supply, before the length cap.
    var available: Int {
        switch self {
        case .custom(let module): return module.effectiveCount
        case .series(let paper): return paper.questions
        }
    }
}

/// A room to open. `String` is not `Identifiable`, and a game id is exactly the identity a
/// `fullScreenCover(item:)` wants.
struct MedxRoomRequest: Identifiable, Hashable {
    let id: String
}

// MARK: - The lobby

/// Pushed from Library. The room itself is a cover the shell hosts, so a Join here, an invite on
/// Home and a notification all open the same thing the same way.
public struct FaceoffLobbyView: View {
    @StateObject private var lobby = MedxFaceoffLobby()
    @ObservedObject private var watcher = MedxLobbyWatcher.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var authService = AuthService.shared

    @State private var showHostSheet = false
    /// A game dealt inside the host sheet, opened once the sheet has gone — raising the room's
    /// cover in the same update that dismisses the sheet hands it to the sheet's presentation.
    @State private var dealtRoom: String?

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    private var other: Profile? {
        Profile.allProfiles.first { $0.uid != uid }
    }

    private var subtitle: String {
        let total = lobby.record.total
        guard total > 0 else { return "One question, one minute, two of you" }
        return total == 1 ? "1 played" : "\(total) played"
    }

    public var body: some View {
        List {
            if lobby.remoteWorks == false {
                Section {
                    Label(
                        "Faceoff cannot reach its game server right now, so it cannot run. Nothing else in the app is affected.",
                        systemImage: "icloud.slash"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            if !lobby.theirs.isEmpty {
                Section("Waiting for you") {
                    ForEach(lobby.theirs) { game in
                        inviteRow(game)
                    }
                }
            }

            if !lobby.mine.isEmpty {
                Section("Your open lobby") {
                    ForEach(lobby.mine) { game in
                        waitingRow(game)
                    }
                }
            }

            Section {
                Button {
                    HapticManager.medium()
                    showHostSheet = true
                } label: {
                    HStack(spacing: MedxSpace.m) {
                        MedxTileLabel(
                            "Host a faceoff",
                            detail: "Deal a paper and \(other?.displayName ?? "the other one") gets a Join button on their Home screen",
                            symbol: "plus",
                            hue: MedxFeature.faceoff.color
                        )
                        .foregroundStyle(.primary)
                        Spacer(minLength: MedxSpace.s)
                        MedxRowChevron()
                    }
                }
                .disabled(lobby.remoteWorks == false || uid == nil)
            } footer: {
                Text("A right answer is \(MedxDuelRules.basePoints) points plus whatever is still on the clock: \(MedxDuelRules.maxPoints) if you are instant, \(MedxDuelRules.basePoints) if you scrape it, nothing if you are wrong. A faceoff counts as a sitting for both of you.")
            }

            if lobby.record.total > 0 {
                recordSection
                historySection
            } else if lobby.history != nil, lobby.theirs.isEmpty, lobby.mine.isEmpty {
                Section {
                    MedxEmptyState(
                        "No faceoffs yet",
                        symbol: MedxFeature.faceoff.symbol,
                        message: "Deal a paper and \(other?.displayName ?? "the other one") gets a Join button on their Home screen the moment it lands."
                    )
                }
            }

            if let failure = lobby.failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(MedxOutcome.wrong)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(MedxFeature.faceoff.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await lobby.reloadHistory() }
        .task { lobby.start() }
        .onReceive(NotificationCenter.default.publisher(for: .medxSittingDidFinish)) { _ in
            Task { await lobby.reloadHistory() }
        }
        .sheet(isPresented: $showHostSheet, onDismiss: openDealtRoom) {
            FaceoffHostSheet(lobby: lobby) { gameId in
                dealtRoom = gameId
                showHostSheet = false
            }
        }
    }

    private func openDealtRoom() {
        guard let dealtRoom else { return }
        self.dealtRoom = nil
        appState.openDuelId = dealtRoom
    }

    // MARK: - Rows

    private func inviteRow(_ game: MedxDuelGame) -> some View {
        let host = Profile.byId(game.hostProfile) ?? Profile.byUid(game.hostUid)

        return HStack(spacing: MedxSpace.m) {
            if let host {
                ProfileAvatarView(profile: host, size: 36)
            } else {
                MedxSymbolTile(MedxFeature.faceoff.symbol, hue: MedxFeature.faceoff.color, size: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(host?.displayName ?? "Someone") is waiting")
                Text("\(game.source?.name ?? "A paper") · \(game.total) questions")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: MedxSpace.s)

            Button(lobby.busy == game.id ? "Joining…" : "Join") {
                HapticManager.medium()
                Task {
                    if let id = await lobby.join(game) {
                        appState.openDuelId = id
                    }
                }
            }
            .medxPrimary(size: .small)
            .disabled(lobby.busy != nil)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(host?.displayName ?? "Someone") is waiting to play")
    }

    private func waitingRow(_ game: MedxDuelGame) -> some View {
        Button {
            appState.openDuelId = game.id
        } label: {
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile("hourglass", hue: MedxOutcome.pending, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for \(other?.displayName ?? "the other one")")
                        .foregroundStyle(.primary)
                    Text("\(game.source?.name ?? "A paper") · \(game.total) questions")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: MedxSpace.s)

                MedxRowChevron()
            }
            .padding(.vertical, 2)
            .foregroundStyle(Color.primary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await lobby.cancel(game) }
            } label: {
                Label("Cancel lobby", systemImage: "trash")
            }
        }
        .disabled(lobby.busy != nil)
        .accessibilityLabel("Your open lobby")
        .accessibilityHint("Opens the room. Swipe left to cancel it.")
    }

    private var recordSection: some View {
        let record = lobby.record

        return Section {
            MedxStatRow {
                ForEach(Profile.allProfiles) { profile in
                    MedxStatTile(
                        "\(record.wins[profile.uid] ?? 0)",
                        label: "\(profile.displayName) won",
                        symbol: "trophy.fill",
                        hue: profile.duelTint
                    )
                }
                MedxStatTile("\(record.draws)", label: "dead heats", symbol: "equal.circle.fill", hue: MedxOutcome.pending)
            }
            .padding(.vertical, MedxSpace.xs)
        } header: {
            Text("The record")
        }
    }

    private var historySection: some View {
        Section("Recent") {
            ForEach(lobby.played.prefix(8)) { game in
                historyRow(game)
            }
        }
    }

    private func historyRow(_ game: MedxDuelGame) -> some View {
        let scores = MedxDuelRules.finalScores(log: game.log, uids: game.uids)
        let won = MedxDuelRules.leader(scores: scores, uids: game.uids)
        let winner = won.flatMap { Profile.byUid($0) }
        let line = game.uids.map { "\(scores[$0]?.points ?? 0)" }.joined(separator: " – ")

        return Button {
            appState.openDuelId = game.id
        } label: {
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile(
                    winner == nil ? "equal" : "trophy.fill",
                    hue: winner?.duelTint ?? MedxOutcome.pending,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(game.source?.name ?? "Faceoff")
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(game.total) questions · \(line)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: MedxSpace.s)

                Text(winner.map { "\($0.displayName) won" } ?? "Dead heat")
                    .font(.footnote)
                    .foregroundStyle(winner?.duelTint ?? Color.secondary)

                MedxRowChevron()
            }
            .padding(.vertical, 2)
            .foregroundStyle(Color.primary)
        }
        .accessibilityLabel(game.source?.name ?? "Faceoff")
        .accessibilityValue(winner.map { "\($0.displayName) won, \(line)" } ?? "dead heat, \(line)")
    }
}

// MARK: - Host sheet

/// Which library the host is picking from.
enum MedxFaceoffTab: Hashable {
    case custom
    case group(MedxSeriesGroup)

    var label: String {
        switch self {
        case .custom: return "Custom"
        case .group(let group): return group.label
        }
    }

    static let all: [MedxFaceoffTab] =
        [.custom] + MedxSeriesGroup.allCases.map { MedxFaceoffTab.group($0) }
}

/// Pick a source and a length, deal. A list with a search field, Deal in the bar.
struct FaceoffHostSheet: View {
    @ObservedObject var lobby: MedxFaceoffLobby
    let onDealt: (String) -> Void

    @ObservedObject private var customStore = MedxCustomModuleStore.shared
    @ObservedObject private var authService = AuthService.shared

    @State private var tab: MedxFaceoffTab = .custom
    @State private var query = ""
    @State private var picked: MedxFaceoffPick?
    @State private var length = 20
    @State private var series: MedxSeriesIndex?
    @State private var isLoadingSeries = false
    @State private var draft: MedxCustomModule?

    @Environment(\.dismiss) private var dismiss

    /// How many papers a source tab lists before it asks you to search. 352 rows in a sheet is not
    /// a list, it is a scroll.
    private static let listCap = 40
    private static let lengthKey = "medx.duel.length"

    private var uid: String? { authService.currentSession?.uid }

    /// What the deal will actually ask, once the length cap meets what the source can supply.
    private var dealt: Int {
        guard let picked else { return 0 }
        return length > 0 ? min(length, picked.available) : picked.available
    }

    private var dealLine: String {
        if let failure = lobby.failure { return failure }
        guard picked != nil else { return "Pick a source below." }
        return "\(dealt) question\(dealt == 1 ? "" : "s"), shuffled, a minute each, "
            + "\(MedxFormat.count(MedxDuelRules.possiblePoints(dealt))) points on the table. Both of you see the same deck."
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Source", selection: $tab) {
                        ForEach(MedxFaceoffTab.all, id: \.self) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Length", selection: $length) {
                        ForEach(MedxDuelRules.lengths, id: \.self) { value in
                            Text(value == 0 ? "All" : "\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Questions")
                } footer: {
                    Text(dealLine)
                        .foregroundStyle(lobby.failure == nil ? Color.secondary : MedxOutcome.wrong)
                }

                sourceSection
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: tab == .custom ? "Find a custom module" : "Find a paper")
            .navigationTitle("Host a faceoff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if lobby.busy == "deal" {
                        ProgressView()
                    } else {
                        Button("Deal") { deal() }
                            .disabled(picked == nil)
                    }
                }
            }
            .task {
                let saved = UserDefaults.standard.integer(forKey: Self.lengthKey)
                length = MedxDuelRules.lengths.contains(saved) ? saved : 20
                await customStore.loadIfNeeded(uid: uid)
                await loadSeriesIfNeeded()
            }
            .onChange(of: length) { _, next in
                UserDefaults.standard.set(next, forKey: Self.lengthKey)
            }
            .onChange(of: tab) { _, _ in
                query = ""
                Task { await loadSeriesIfNeeded() }
            }
            .sheet(item: $draft) { editing in
                ModuleBuilderSheet(draft: editing, isEditing: false) { saved in
                    draft = nil
                    if let uid {
                        Task {
                            let landed = await customStore.save(saved, uid: uid)
                            picked = .custom(landed)
                        }
                    }
                } onCancel: {
                    draft = nil
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.page)
    }

    private func deal() {
        guard let picked else { return }
        HapticManager.medium()
        Task {
            if let gameId = await lobby.deal(pick: picked, length: length) {
                onDealt(gameId)
            }
        }
    }

    // MARK: - Sources

    @ViewBuilder
    private var sourceSection: some View {
        switch tab {
        case .custom: customSection
        case .group(let group): paperSection(group)
        }
    }

    private var customSection: some View {
        Section {
            Button {
                guard let uid else { return }
                HapticManager.medium()
                draft = MedxCustomModule.blank(uid: uid)
            } label: {
                HStack(spacing: MedxSpace.m) {
                    MedxTileLabel(
                        "Build a new one",
                        detail: "Pick chapters out of either bank, then deal it straight into the game",
                        symbol: "plus",
                        hue: MedxFeature.customModules.color
                    )
                    .foregroundStyle(.primary)
                    Spacer(minLength: MedxSpace.s)
                    MedxRowChevron()
                }
            }

            let matches = customMatches
            if customStore.isLoading, matches.isEmpty {
                MedxPlaceholderRows(count: 3)
            } else if matches.isEmpty {
                Text("No custom modules yet. Build one above, or pick a Marrow paper from the other tabs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(matches) { module in
                sourceRow(
                    symbol: MedxFeature.customModules.symbol,
                    hue: MedxFeature.customModules.color,
                    title: module.name,
                    detail: "\(module.effectiveCount) questions · \(module.sources.count) module"
                        + (module.sources.count == 1 ? "" : "s")
                        + (module.author.map { " · \($0.displayName)" } ?? ""),
                    isOn: picked == .custom(module)
                ) {
                    picked = .custom(module)
                }
            }
        } header: {
            Text("Custom modules")
        }
    }

    private var customMatches: [MedxCustomModule] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return customStore.modules }
        return customStore.modules.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    private func paperSection(_ group: MedxSeriesGroup) -> some View {
        let papers = paperMatches(group)

        return Section {
            if isLoadingSeries, series == nil {
                MedxPlaceholderRows(count: 6)
            }

            ForEach(Array(papers.prefix(Self.listCap))) { paper in
                sourceRow(
                    symbol: MedxSeriesRules.symbol(for: paper),
                    hue: MedxFeature.tests.color,
                    title: paper.title,
                    detail: paper.line,
                    isOn: picked == .series(paper)
                ) {
                    picked = .series(paper)
                }
            }

            if papers.count > Self.listCap {
                Text("\(papers.count - Self.listCap) more. Search to narrow it down.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if series != nil, papers.isEmpty {
                Text("Nothing matches that.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(group.label)
        }
    }

    private func paperMatches(_ group: MedxSeriesGroup) -> [MedxSeriesPaper] {
        let all = (series?.papers ?? []).filter { $0.group == group }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hits = needle.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        return hits.sorted { $0.startAt > $1.startAt }
    }

    private func sourceRow(
        symbol: String,
        hue: Color,
        title: String,
        detail: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile(symbol, hue: hue, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: MedxSpace.s)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? MedxTheme.accent : Color.secondary)
            }
            .padding(.vertical, 2)
            .foregroundStyle(Color.primary)
        }
        .accessibilityLabel(title)
        .accessibilityValue(detail)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// The catalogue is one document but a big one, and the lobby does not need it until a paper tab
    /// is opened — so it is fetched on demand rather than at launch.
    private func loadSeriesIfNeeded() async {
        guard case .group = tab, series == nil, !isLoadingSeries else { return }
        isLoadingSeries = true
        defer { isLoadingSeries = false }
        guard let token = try? await authService.getValidIdToken() else { return }
        series = try? await FirestoreService.shared.fetchSeriesIndex(idToken: token)
    }
}
