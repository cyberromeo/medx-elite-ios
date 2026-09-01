import SwiftUI

// MARK: - Lobby state

/// The lobby's own data: every open lobby, and this profile's finished games.
///
/// There are two people using this app, so there are no game codes — the join card is a live
/// subscription to every open lobby, filtered to the other one's. Joining is a single tap, and it is
/// also the readiness signal: the host's Start button is dead until it writes a player row.
@MainActor
final class MedxFaceoffLobby: ObservableObject {
    @Published private(set) var lobbies: [MedxDuelGame]?
    @Published private(set) var history: [MedxDuelGame]?
    @Published var failure: String?
    @Published var busy: String?

    let transport: MedxDuelTransport
    private var subscription: MedxDuelSubscription?

    init(transport: MedxDuelTransport? = nil) {
        self.transport = transport ?? MedxDuelTransportFactory.make()
    }

    deinit { subscription?.cancel() }

    var remoteWorks: Bool? { transport.remoteWorks }

    private var uid: String? { AuthService.shared.currentSession?.uid }

    /// Gated on a uid: a read that fires before auth resolves reports a permission error that is a
    /// race, not a rules problem.
    func start() {
        guard uid != nil, subscription == nil else { return }
        transport.setUrgency(.lobby)
        subscription = transport.watchOpenLobbies { [weak self] games in
            self?.lobbies = games
        }
        Task { await reloadHistory() }
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
    }

    func reloadHistory() async {
        guard let uid else { return }
        do {
            history = try await transport.listMyDuels(uid: uid)
        } catch {
            failure = "Your past faceoffs could not be read."
        }
    }

    /// A lobby the *other* one dealt and nobody has joined. Stale ones go cold rather than sitting
    /// in the list forever.
    var theirs: [MedxDuelGame] {
        (lobbies ?? []).filter { $0.hostUid != uid && MedxDuelRules.isOfferable($0) }
    }

    var mine: [MedxDuelGame] {
        (lobbies ?? []).filter { $0.hostUid == uid && MedxDuelRules.isOfferable($0) }
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
            failure = "Joining did not go through. Firestore refused the write."
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
            failure = "Firestore would not take the deal."
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

public struct FaceoffLobbyView: View {
    @StateObject private var lobby = MedxFaceoffLobby()
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var authService = AuthService.shared

    @State private var showHostSheet = false
    @State private var openRoom: MedxRoomRequest?

    @Environment(\.dismiss) private var dismiss

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    private var other: Profile? {
        Profile.allProfiles.first { $0.uid != uid }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header

                    if lobby.remoteWorks == false {
                        warning
                    }

                    ForEach(lobby.theirs) { game in
                        inviteCard(game)
                    }

                    ForEach(lobby.mine) { game in
                        waitingCard(game)
                    }

                    hostButton

                    if lobby.record.total > 0 {
                        recordSection
                        historySection
                    } else if lobby.history != nil, lobby.theirs.isEmpty, lobby.mine.isEmpty {
                        emptyState
                    }

                    footer
                }
                .padding(.horizontal, MedxSurface.gutter)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
            .medxScrollEdge()
            .navigationTitle("Faceoff")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .refreshable { await lobby.reloadHistory() }
            .onAppear {
                lobby.start()
                // A deep link or a Home invite card can ask for a specific room before this screen
                // even exists, so the request is picked up here rather than raced for.
                if let pending = appState.openDuelId {
                    appState.openDuelId = nil
                    openRoom = MedxRoomRequest(id: pending)
                }
            }
            .onDisappear { lobby.stop() }
            .sheet(isPresented: $showHostSheet) {
                FaceoffHostSheet(lobby: lobby) { gameId in
                    showHostSheet = false
                    openRoom = MedxRoomRequest(id: gameId)
                }
            }
            .fullScreenCover(item: $openRoom) { request in
                DuelRoomView(gameId: request.id) {
                    openRoom = nil
                    Task { await lobby.reloadHistory() }
                }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        MedxPageHeader(
            section: .duel,
            lead: "One question, one minute, two of you. A right answer is 40 points plus whatever "
                + "is still on the clock — \(MedxDuelRules.maxPoints) if you are instant, "
                + "\(MedxDuelRules.basePoints) if you scrape it, nothing if you are wrong."
        )
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "icloud.slash")
                .font(.caption.weight(.bold))
                .foregroundStyle(MedxTheme.warningOrange)
            Text("Firestore would not take the duel collections, so Faceoff cannot run. Nothing "
                 + "else in the app is affected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .medxCard()
    }

    private func inviteCard(_ game: MedxDuelGame) -> some View {
        let host = Profile.byId(game.hostProfile) ?? Profile.byUid(game.hostUid)
        let hue = host?.duelFill ?? MedxCandy.pink

        return HStack(spacing: 12) {
            MedxSticker(host?.sticker ?? "bolt", size: 30, tilt: -7)
                .frame(width: 40, height: 40)
                .background(hue.opacity(0.2), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(host?.displayName ?? "Someone") is waiting")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(game.source?.name ?? "a paper") · \(game.total) q")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                Task {
                    if let id = await lobby.join(game) {
                        openRoom = MedxRoomRequest(id: id)
                    }
                }
            } label: {
                Text(lobby.busy == game.id ? "Joining" : "Join")
                    .font(.subheadline.weight(.bold))
                    .frame(minWidth: 62, minHeight: 34)
                    .padding(.horizontal, 6)
            }
            .medxFilled(hue)
            .disabled(lobby.busy != nil)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard(raised: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(host?.displayName ?? "Someone") is waiting to play")
    }

    private func waitingCard(_ game: MedxDuelGame) -> some View {
        HStack(spacing: 12) {
            MedxSticker("hourglass", size: 26, tilt: 6)
                .frame(width: 38, height: 38)
                .background(MedxSurface.fieldFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for \(other?.displayName ?? "the other one")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(game.source?.name ?? "a paper") · \(game.total) q")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button("Open") {
                openRoom = MedxRoomRequest(id: game.id)
            }
            .font(.subheadline.weight(.semibold))
            .medxBorderedButton()
            .buttonBorderShape(.capsule)

            Button(role: .destructive) {
                Task { await lobby.cancel(game) }
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.bold))
                    .frame(width: 34, height: 30)
            }
            .medxBorderedButton()
            .buttonBorderShape(.capsule)
            .disabled(lobby.busy != nil)
            .accessibilityLabel("Cancel this lobby")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
    }

    private var hostButton: some View {
        Button {
            HapticManager.medium()
            showHostSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                Text("Host a faceoff")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .medxFilled(MedxSection.duel.fill)
        .disabled(lobby.remoteWorks == false)
    }

    private var recordSection: some View {
        let record = lobby.record

        return VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader("The record", subtitle: "\(record.total) played")

            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(Profile.allProfiles) { profile in
                        VStack(spacing: 4) {
                            MedxSticker(profile.sticker, size: 30, tilt: profile.id == Profile.graveyard.id ? -8 : 8)
                            Text("\(record.wins[profile.uid] ?? 0)")
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(profile.duelFill)
                            Text(profile.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if record.draws > 0 {
                    Text(record.draws == 1 ? "1 dead heat" : "\(record.draws) dead heats")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .medxCard()
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MedxSectionHeader("Recent")

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
            openRoom = MedxRoomRequest(id: game.id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.source?.name ?? "Faceoff")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(game.total) q · \(line)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let winner {
                    MedxPill(winner.displayName, hue: winner.duelFill, weight: .solid)
                } else {
                    MedxPill("dead heat", weight: .outline)
                }

                MedxDisclosure()
            }
            .padding(12)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(game.source?.name ?? "Faceoff")
        .accessibilityValue(winner.map { "\($0.displayName) won, \(line)" } ?? "dead heat, \(line)")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            MedxSticker("bolt", size: 62, tilt: -8)
            Text("No faceoffs yet")
                .font(.headline)
            Text("Deal a paper and \(other?.displayName ?? "the other one") gets a Join button on "
                 + "their Home screen the moment it lands.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 12)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text("A faceoff counts as a sitting for both of you, so the questions land in your "
                 + "accuracy, your streak and your daily goal like any other paper.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        MedxSegmented(
                            section: .duel,
                            segments: MedxFaceoffTab.all.map { MedxSegment(value: $0, label: $0.label) },
                            selection: $tab
                        )
                        .onChange(of: tab) { _, _ in query = "" }

                        lengthRow
                        searchField
                        list
                    }
                    .padding(.horizontal, MedxSurface.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }

                dealBar
            }
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
            .navigationTitle("Host a faceoff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                length = MedxDuelRules.lengths.contains(UserDefaults.standard.integer(forKey: Self.lengthKey))
                    ? UserDefaults.standard.integer(forKey: Self.lengthKey)
                    : 20
                await customStore.loadIfNeeded(uid: uid)
                await loadSeriesIfNeeded()
            }
            .onChange(of: tab) { _, _ in
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
    }

    private var lengthRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Length")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            MedxSegmented(
                section: .duel,
                segments: MedxDuelRules.lengths.map {
                    MedxSegment(value: $0, label: $0 == 0 ? "All" : "\($0)")
                },
                selection: $length
            )
            .onChange(of: length) { _, next in
                UserDefaults.standard.set(next, forKey: Self.lengthKey)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(tab == .custom ? "Find a custom module" : "Find a paper", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(MedxSurface.fieldFill, in: Capsule())
    }

    // MARK: - The list

    @ViewBuilder
    private var list: some View {
        switch tab {
        case .custom: customList
        case .group(let group): paperList(group)
        }
    }

    private var customList: some View {
        VStack(spacing: 8) {
            Button {
                guard let uid else { return }
                HapticManager.medium()
                draft = MedxCustomModule.blank(uid: uid)
            } label: {
                sourceRow(
                    symbol: "plus.rectangle.on.rectangle",
                    title: "Build a new one",
                    detail: "Pick chapters out of either bank, then deal it straight into the game",
                    isOn: false
                )
            }
            .buttonStyle(.plain)

            let matches = customMatches
            if customStore.isLoading, matches.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if matches.isEmpty {
                Text("No custom modules yet — build one above, or pick a Marrow paper from the "
                     + "other tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            ForEach(matches) { module in
                Button {
                    HapticManager.selection()
                    picked = .custom(module)
                } label: {
                    sourceRow(
                        symbol: "slider.horizontal.3",
                        title: module.name,
                        detail: "\(module.effectiveCount) q · \(module.sources.count) module"
                            + (module.sources.count == 1 ? "" : "s")
                            + (module.author.map { " · \($0.displayName)" } ?? ""),
                        isOn: picked == .custom(module)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customMatches: [MedxCustomModule] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return customStore.modules }
        return customStore.modules.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    private func paperList(_ group: MedxSeriesGroup) -> some View {
        let papers = paperMatches(group)

        return VStack(spacing: 8) {
            if isLoadingSeries, series == nil {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            }

            ForEach(Array(papers.prefix(Self.listCap)).indices, id: \.self) { index in
                let paper = papers[index]
                Button {
                    HapticManager.selection()
                    picked = .series(paper)
                } label: {
                    sourceRow(
                        symbol: MedxSeriesRules.symbol(for: paper),
                        title: paper.title,
                        detail: paper.line,
                        isOn: picked == .series(paper)
                    )
                }
                .buttonStyle(.plain)
            }

            if papers.count > Self.listCap {
                Text("\(papers.count - Self.listCap) more — search to narrow it down.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            if series != nil, papers.isEmpty {
                Text("Nothing matches that.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func paperMatches(_ group: MedxSeriesGroup) -> [MedxSeriesPaper] {
        let all = (series?.papers ?? []).filter { $0.group == group }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hits = needle.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        return hits.sorted { $0.startAt > $1.startAt }
    }

    // MARK: - Row and bar

    private func sourceRow(
        symbol: String,
        title: String,
        detail: String,
        isOn: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? MedxSection.duel.onSoft : Color.secondary)
                .frame(width: 34, height: 34)
                .background(
                    isOn ? MedxSection.duel.soft : MedxSurface.fieldFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isOn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(MedxSection.duel.fill)
            }
        }
        .padding(12)
        .frame(minHeight: 54)
        .medxTile(accentColor: MedxSection.duel.fill, isSelected: isOn)
        .contentShape(RoundedRectangle(cornerRadius: MedxSurface.tileRadius, style: .continuous))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var dealBar: some View {
        VStack(spacing: 6) {
            if let failure = lobby.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(MedxTheme.warningOrange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if picked != nil {
                Text("\(dealt) question\(dealt == 1 ? "" : "s"), shuffled, a minute each — "
                     + "\(MedxDuelRules.possiblePoints(dealt)) points on the table. "
                     + "Both of you see the same deck.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                guard let picked else { return }
                Task {
                    if let gameId = await lobby.deal(pick: picked, length: length) {
                        onDealt(gameId)
                    }
                }
            } label: {
                Text(dealLabel)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .medxFilled(MedxSection.duel.fill)
            .disabled(picked == nil || lobby.busy == "deal")
        }
        .padding(.horizontal, MedxSurface.gutter)
        .padding(.vertical, 10)
        .medxBar(topDivider: true)
    }

    private var dealLabel: String {
        if lobby.busy == "deal" { return "Dealing…" }
        guard picked != nil else { return "Pick a source" }
        return "Deal \(dealt) questions"
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
