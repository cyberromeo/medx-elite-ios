import SwiftUI

// MARK: - Versus bar

/// The score *and* the progress indicator for who is winning, which is why it is a bar rather than
/// two numbers: at a glance you want "am I behind", not the arithmetic.
///
/// Level pegging — including 0–0 before the first question — splits down the middle rather than
/// collapsing to one side.
struct MedxVersusBar: View {
    let mine: MedxDuelScore
    let theirs: MedxDuelScore
    let myProfile: Profile?
    let theirProfile: Profile?

    private var share: Double {
        let total = mine.points + theirs.points
        return total > 0 ? Double(mine.points) / Double(total) : 0.5
    }

    private var myTint: Color { myProfile?.duelTint ?? MedxTheme.accent }
    private var theirTint: Color { theirProfile?.duelTint ?? Color(uiColor: .systemOrange) }

    var body: some View {
        VStack(spacing: MedxSpace.xs) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(myTint)
                        .frame(width: max(4, geo.size.width * share))
                    Rectangle()
                        .fill(theirTint)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .animation(.snappy(duration: 0.35), value: share)

            HStack {
                side(points: mine.points, name: myProfile?.displayName ?? "you", tint: myTint, alignment: .leading)
                Spacer(minLength: MedxSpace.s)
                side(points: theirs.points, name: theirProfile?.displayName ?? "them", tint: theirTint, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score")
        .accessibilityValue("\(myProfile?.displayName ?? "you") \(mine.points), "
                            + "\(theirProfile?.displayName ?? "them") \(theirs.points)")
    }

    private func side(points: Int, name: String, tint: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            MedxFigure("\(points)", style: .title3)
                .foregroundStyle(tint)
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - The room

/// One live duel, from the lobby to the scoreboard.
///
/// A cover the shell hosts, with no tab bar: a question with a minute on it and a tab bar over it
/// is an invitation to lose your place by mistake. The bars are the runner's: the question counter
/// is the title, the paper is the subtitle, the clock sits in the trailing slot and Next lives in
/// the bottom bar.
public struct DuelRoomView: View {
    private let gameId: String
    private let onClose: () -> Void

    @StateObject private var room = MedxDuelRoom()
    @State private var showLeaveAlert = false
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 120

    public init(gameId: String, onClose: @escaping () -> Void) {
        self.gameId = gameId
        self.onClose = onClose
    }

    private var isPlaying: Bool {
        room.phase == .asked || room.phase == .waiting || room.phase == .reveal
    }

    private var title: String {
        if isPlaying, room.total > 0 {
            return "Question \(min(room.qIndex + 1, room.total)) of \(room.total)"
        }
        if room.phase == .done { return "Result" }
        return room.source?.name ?? "Faceoff"
    }

    private var subtitle: String {
        if isPlaying || room.phase == .done { return room.source?.name ?? "Faceoff" }
        return room.total > 0 ? "\(room.total) questions · 60 s each" : "Faceoff"
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .alert("Leave this faceoff?", isPresented: $showLeaveAlert) {
                    Button("Keep playing", role: .cancel) {}
                    Button("Leave", role: .destructive) {
                        Task {
                            await room.leave()
                            onClose()
                        }
                    }
                } message: {
                    Text(room.isHost
                         ? "You dealt this one, so leaving abandons it for both of you."
                         : "The game is abandoned for both of you.")
                }
        }
        .task { room.open(gameId: gameId) }
        .onDisappear { room.close() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(role: .close) {
                if room.phase == .done || room.phase == .abandoned {
                    room.close()
                    onClose()
                } else {
                    showLeaveAlert = true
                }
            }
            .accessibilityLabel("Leave faceoff")
        }

        if isPlaying {
            ToolbarItem(placement: .topBarTrailing) {
                clock
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button(nextLabel) {
                    room.voteNext()
                }
                .buttonStyle(.glassProminent)
                .disabled(room.phase != .reveal || room.iVoted)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }
    }

    /// The clock is the loudest thing on the screen because it is what the points are made of.
    private var clock: some View {
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.footnote.weight(.semibold))
            Text("\(room.remaining)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
        }
        .foregroundStyle(clockTint)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(room.remaining) seconds left")
    }

    private var clockTint: Color {
        if room.phase == .reveal { return .secondary }
        return room.remaining <= 10 ? MedxOutcome.wrong : MedxTheme.accent
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        if let failure = room.failure {
            MedxEmptyState(
                "Faceoff cannot run",
                symbol: "icloud.slash",
                message: failure + " Nothing else in the app is affected.",
                actionTitle: "Back"
            ) { onClose() }
        } else if room.isMissing {
            MedxEmptyState(
                "That game is gone",
                symbol: "questionmark.folder",
                message: "It was cancelled, or the link was for a game that no longer exists.",
                actionTitle: "Back to the lobby"
            ) { onClose() }
        } else if room.isLoading {
            ProgressView("Reading the room…")
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch room.phase {
            case .lobby:
                DuelLobbyPane(room: room)
            case .arming:
                arming
            case .asked, .waiting, .reveal:
                playing
            case .done:
                DuelResultView(room: room) {
                    room.close()
                    onClose()
                }
            case .abandoned:
                MedxEmptyState(
                    "Faceoff abandoned",
                    symbol: "bolt.slash",
                    message: room.theyLeft
                        ? "\(room.theirProfile?.displayName ?? "The other one") left the game."
                        : "This game was closed before it finished.",
                    actionTitle: "Back to the lobby"
                ) {
                    room.close()
                    onClose()
                }
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The 3 · 2 · 1. Derived entirely from `askedAt`, which both devices already have, so neither
    /// waits on the other to start counting.
    private var arming: some View {
        VStack(spacing: MedxSpace.l) {
            Spacer()

            Text("\(room.armingIn)")
                .font(.system(size: countdownSize, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(MedxTheme.accent)
                .animation(.snappy(duration: 0.2), value: room.armingIn)

            Text("Question \(room.qIndex + 1) coming up")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            MedxVersusBar(
                mine: room.myScore,
                theirs: room.theirScore,
                myProfile: room.myProfile,
                theirProfile: room.theirProfile
            )
            .padding(.horizontal, MedxSpace.l)
            .padding(.bottom, MedxSpace.xl)
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Starting in \(room.armingIn)")
    }

    // MARK: - The open question

    private var playing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MedxSpace.l) {
                if room.phase != .reveal {
                    Text("+\(MedxDuelRules.basePoints + room.remaining) if you are right")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if let question = room.question {
                    HTMLRichTextView(html: question.html, fontSize: 18, weight: .semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    options(for: question)
                }

                if room.phase == .reveal {
                    DuelRevealPane(room: room)
                    revealStatus
                } else if let beatenBy = room.beatenBy {
                    // Said out loud, because on a shared clock the useful pressure is knowing
                    // they have already committed.
                    Label("\(beatenBy.displayName) answered already", systemImage: "hare.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(beatenBy.duelTint)
                } else if room.phase == .waiting {
                    HStack(spacing: MedxSpace.s) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for \(room.theirProfile?.displayName ?? "them")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, MedxSpace.l)
            .padding(.vertical, MedxSpace.m)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .top, spacing: 0) {
            MedxVersusBar(
                mine: room.myScore,
                theirs: room.theirScore,
                myProfile: room.myProfile,
                theirProfile: room.theirProfile
            )
            .padding(.horizontal, MedxSpace.l)
            .padding(.vertical, MedxSpace.s)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    /// Next needs *both* votes, which is what stops one player racing ahead of an explanation the
    /// other one is still reading.
    @ViewBuilder
    private var revealStatus: some View {
        if room.iVoted, !room.theyVoted {
            Text("Waiting for \(room.theirProfile?.displayName ?? "them") to move on")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if !room.isHost, room.iVoted, room.theyVoted {
            // The host owns `qIndex`, so if their app is asleep nothing advances. Said plainly
            // rather than refereed, because refereeing would mean writing their document.
            Text("Waiting for \(room.theirProfile?.displayName ?? "the host") to open the next question. Their app has to be awake.")
                .font(.footnote)
                .foregroundStyle(MedxOutcome.flagged)
        }
    }

    private func options(for question: MedxDuelQuestion) -> some View {
        VStack(spacing: MedxSpace.s) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                QuestionOptionButton(
                    option: pair.element,
                    index: pair.offset,
                    isChosen: room.shownMine?.optionId == pair.element.id,
                    isCorrect: question.isCorrect(optionId: pair.element.id),
                    // Nothing is revealed until both sides are in, or the minute has gone.
                    isRevealed: room.phase == .reveal,
                    isLocked: room.phase != .asked
                ) {
                    room.answer(pair.element)
                }
            }
        }
    }

    private var nextLabel: String {
        switch room.phase {
        case .asked: return "Pick an answer"
        case .waiting: return "Locked in"
        case .reveal:
            if room.iVoted { return "Ready" }
            return room.qIndex + 1 >= room.total ? "Finish" : "Next question"
        default: return "…"
        }
    }
}

// MARK: - Lobby pane

/// The room before it is a game.
///
/// The guest's seat is a dashed outline until they join, and Start is dead until then: joining
/// *is* the readiness signal. The guest never gets a Start button, so it is always obvious who is
/// being waited on.
struct DuelLobbyPane: View {
    @ObservedObject var room: MedxDuelRoom

    var body: some View {
        List {
            Section {
                HStack(spacing: MedxSpace.l) {
                    seat(profile: room.myProfile, isHere: true)

                    Text("vs")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    seat(
                        profile: room.theirProfile,
                        isHere: room.theirs != nil && !(room.theirs?.left ?? false)
                    )
                }
                .padding(.vertical, MedxSpace.s)
            }

            Section {
                LabeledContent("Paper", value: room.source?.name ?? "Faceoff")
                LabeledContent("Questions", value: "\(room.total)")
                LabeledContent("On the table", value: "\(MedxFormat.count(MedxDuelRules.possiblePoints(room.total))) points")
            } footer: {
                Text("A minute a question. \(MedxDuelRules.basePoints) for a right answer plus whatever is left on the clock.")
            }

            Section {
                action
            } footer: {
                hint
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var action: some View {
        if !room.isHost, room.mine == nil {
            Button {
                room.join()
            } label: {
                Label("Join this faceoff", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .medxPrimary()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } else if room.isHost {
            Button {
                room.start()
            } label: {
                Text(room.canStart ? "Start" : "Waiting to be joined")
                    .frame(maxWidth: .infinity)
            }
            .medxPrimary()
            .disabled(!room.canStart)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } else {
            Text("You are in. Waiting for \(room.theirProfile?.displayName ?? "the host") to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var hint: some View {
        if room.isHost, !room.canStart {
            Text("\(room.theirProfile?.displayName ?? "The other one") gets a Join button on their Home screen while this is open.")
        }
    }

    private func seat(profile: Profile?, isHere: Bool) -> some View {
        VStack(spacing: MedxSpace.s) {
            if isHere, let profile {
                ProfileAvatarView(profile: profile, size: 56)
                Text(profile.displayName)
                    .font(.headline)
                Text(profile.duelTag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                    .frame(height: 56)
                Text("Waiting")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("not in yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MedxSpace.m)
        .background {
            let shape = RoundedRectangle(cornerRadius: MedxRadius.control, style: .continuous)
            if isHere {
                shape.fill((profile?.duelTint ?? MedxTheme.accent).opacity(0.12))
            } else {
                shape.strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Reveal pane

/// The round, scored, with the sum spelled out.
///
/// `40 + 28 = 68` rather than just `68`, because the whole points system is "being right is the
/// floor, the clock is the rest" and one line of arithmetic teaches it faster than a rules screen.
struct DuelRevealPane: View {
    @ObservedObject var room: MedxDuelRoom

    var body: some View {
        VStack(alignment: .leading, spacing: MedxSpace.m) {
            if let first = firstProfile {
                Label("\(first.displayName) was first in", systemImage: "hare.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(first.duelTint)
            }

            VStack(spacing: MedxSpace.s) {
                line(profile: room.myProfile, answer: room.shownMine)
                line(profile: room.theirProfile, answer: room.shownTheirs)
            }

            if let question = room.question, !question.explanation.isEmpty {
                VStack(alignment: .leading, spacing: MedxSpace.s) {
                    Label("Explanation", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                    HTMLRichTextView(html: question.explanation, fontSize: 15, weight: .regular, textColor: .secondary)
                    if !question.reference.isEmpty {
                        Label(question.reference, systemImage: "book.closed")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(MedxSpace.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .medxOptionSurface(state: nil)
            }
        }
    }

    private var firstProfile: Profile? {
        guard let uid = room.tally?.first else { return nil }
        return Profile.byUid(uid)
    }

    private func line(profile: Profile?, answer: MedxDuelRound?) -> some View {
        let points = MedxDuelRules.score(answer)
        let label = room.question?.options.first { $0.id == answer?.optionId }?.label

        return HStack(spacing: MedxSpace.m) {
            Text(profile?.displayName ?? "-")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(profile?.duelTint ?? Color.secondary)
                .frame(minWidth: 62, alignment: .leading)

            Text(pickText(answer: answer, label: label))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer(minLength: MedxSpace.s)

            Text(sumText(answer: answer, points: points))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(points > 0 ? MedxOutcome.correct : Color.secondary)
        }
        .padding(MedxSpace.m)
        .frame(maxWidth: .infinity)
        .medxOptionSurface(state: nil)
        .accessibilityElement(children: .combine)
    }

    private func pickText(answer: MedxDuelRound?, label: String?) -> String {
        guard let answer, !answer.timedOut, let label else { return "no answer" }
        return "\(label) · \(answer.remaining)s left"
    }

    private func sumText(answer: MedxDuelRound?, points: Int) -> String {
        guard points > 0, let answer else { return "0" }
        return "\(MedxDuelRules.basePoints) + \(answer.remaining) = \(points)"
    }
}
