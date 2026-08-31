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

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(myProfile?.duelFill ?? MedxCandy.pink)
                        .frame(width: max(4, geo.size.width * share))
                    Rectangle()
                        .fill(theirProfile?.duelFill ?? MedxCandy.sky)
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            .animation(.snappy(duration: 0.35), value: share)

            HStack {
                side(points: mine.points, name: myProfile?.displayName ?? "you", hue: myProfile?.duelFill, alignment: .leading)
                Spacer(minLength: 8)
                side(points: theirs.points, name: theirProfile?.displayName ?? "them", hue: theirProfile?.duelFill, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score")
        .accessibilityValue("\(myProfile?.displayName ?? "you") \(mine.points), "
                            + "\(theirProfile?.displayName ?? "them") \(theirs.points)")
    }

    private func side(
        points: Int,
        name: String,
        hue: Color?,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text("\(points)")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(hue ?? .primary)
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - The room

/// One live duel, from the lobby to the scoreboard.
///
/// Presented as a `fullScreenCover` with no tab bar: a question with a minute on it and a tab bar
/// over it is an invitation to lose your place by mistake.
public struct DuelRoomView: View {
    private let gameId: String
    private let onClose: () -> Void

    @StateObject private var room = MedxDuelRoom()
    @State private var showLeaveAlert = false

    public init(gameId: String, onClose: @escaping () -> Void) {
        self.gameId = gameId
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            content
                .medxPage(.duel)
                .navigationTitle(room.source?.name ?? "Faceoff")
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
            Button {
                if room.phase == .done || room.phase == .abandoned {
                    room.close()
                    onClose()
                } else {
                    showLeaveAlert = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Leave faceoff")
        }

        ToolbarItem(placement: .principal) {
            if room.phase != .lobby, room.total > 0 {
                Text("Question \(min(room.qIndex + 1, room.total)) of \(room.total)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        if let failure = room.failure {
            failed(failure)
        } else if room.isMissing {
            missing
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
                abandoned
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The 3 · 2 · 1. Derived entirely from `askedAt`, which both devices already have, so neither
    /// waits on the other to start counting.
    private var arming: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("\(room.armingIn)")
                .font(.system(size: 132, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(MedxSection.duel.fill)
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
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Starting in \(room.armingIn)")
    }

    private var abandoned: some View {
        ContentUnavailableView {
            Label("Faceoff abandoned", systemImage: "bolt.slash")
        } description: {
            Text(room.theyLeft
                 ? "\(room.theirProfile?.displayName ?? "The other one") left the game."
                 : "This game was closed before it finished.")
        } actions: {
            Button("Back to the lobby") {
                room.close()
                onClose()
            }
            .medxFilledButton()
            .buttonBorderShape(.capsule)
        }
    }

    private var missing: some View {
        ContentUnavailableView {
            Label("That game is gone", systemImage: "questionmark.folder")
        } description: {
            Text("It was cancelled, or the link was for a game that no longer exists.")
        } actions: {
            Button("Back to the lobby") { onClose() }
                .medxFilledButton()
                .buttonBorderShape(.capsule)
        }
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Faceoff cannot run", systemImage: "icloud.slash")
        } description: {
            Text(message + " Nothing else in the app is affected.")
        } actions: {
            Button("Back") { onClose() }
                .medxFilledButton()
                .buttonBorderShape(.capsule)
        }
    }

    // MARK: - The open question

    private var playing: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let question = room.question {
                        HTMLRichTextView(html: question.html, fontSize: 17, weight: .semibold)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .medxCard()

                        options(for: question)
                    }

                    if room.phase == .reveal {
                        DuelRevealPane(room: room)
                    } else if let beatenBy = room.beatenBy {
                        // Said out loud, because on a shared clock the useful pressure is knowing
                        // they have already committed.
                        HStack(spacing: 6) {
                            MedxSticker(beatenBy.sticker, size: 18)
                            Text("\(beatenBy.displayName) answered already")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(beatenBy.duelFill)
                        }
                        .padding(.horizontal, 4)
                    } else if room.phase == .waiting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for \(room.theirProfile?.displayName ?? "them")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, MedxSurface.gutter)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .top, spacing: 0) { clockStrip }

            bottomBar
        }
    }

    /// The clock, and the score under it. The clock is the loudest thing on the screen because it is
    /// what the points are made of.
    private var clockStrip: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(room.remaining)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(clockTint)

                Text("s")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if room.phase != .reveal {
                    Text("+\(MedxDuelRules.basePoints + room.remaining) if you are right")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            MedxVersusBar(
                mine: room.myScore,
                theirs: room.theirScore,
                myProfile: room.myProfile,
                theirProfile: room.theirProfile
            )
        }
        .padding(.horizontal, MedxSurface.gutter)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .medxBar()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(room.remaining) seconds left")
    }

    private var clockTint: Color {
        if room.phase == .reveal { return .secondary }
        return room.remaining <= 10 ? MedxTheme.destructiveRed : MedxSection.duel.fill
    }

    private func options(for question: MedxDuelQuestion) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                QuestionOptionButton(
                    option: pair.element,
                    index: pair.offset,
                    isChosen: room.shownMine?.optionId == pair.element.id,
                    isCorrect: question.correctIds.contains(pair.element.id),
                    // Nothing is revealed until both sides are in, or the minute has gone.
                    isRevealed: room.phase == .reveal,
                    isLocked: room.phase != .asked
                ) {
                    room.answer(pair.element)
                }
            }
        }
    }

    /// Next needs *both* votes, which is what stops one player racing ahead of an explanation the
    /// other one is still reading.
    private var bottomBar: some View {
        VStack(spacing: 6) {
            if room.phase == .reveal, room.iVoted, !room.theyVoted {
                Text("Waiting for \(room.theirProfile?.displayName ?? "them") to move on")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if room.phase == .reveal, !room.isHost, room.iVoted, room.theyVoted {
                // The host owns `qIndex`, so if their app is asleep nothing advances. Said plainly
                // rather than refereed, because refereeing would mean writing their document.
                Text("Waiting for \(room.theirProfile?.displayName ?? "the host") to open the next "
                     + "question — their app has to be awake.")
                    .font(.caption)
                    .foregroundStyle(MedxTheme.warningOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                room.voteNext()
            } label: {
                Text(nextLabel)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .medxFilled(MedxSection.duel.fill)
            .disabled(room.phase != .reveal || room.iVoted)
        }
        .padding(.horizontal, MedxSurface.gutter)
        .padding(.vertical, 10)
        .medxBar(topDivider: true)
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
/// The guest's side is an empty dashed outline until they join, and Start is dead until then:
/// joining *is* the readiness signal. The guest never gets a Start button, so it is always obvious
/// who is being waited on.
struct DuelLobbyPane: View {
    @ObservedObject var room: MedxDuelRoom

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
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

                VStack(spacing: 4) {
                    Text(room.source?.name ?? "Faceoff")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("\(room.total) questions · 60s each · "
                         + "\(MedxDuelRules.possiblePoints(room.total)) points on the table")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                action
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var action: some View {
        if !room.isHost, room.mine == nil {
            Button {
                room.join()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("Join this faceoff")
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .medxFilled(room.myProfile?.duelFill ?? MedxSection.duel.fill)
        } else if room.isHost {
            VStack(spacing: 8) {
                Button {
                    room.start()
                } label: {
                    Text(room.canStart ? "Start" : "Waiting to be joined")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .medxFilled(MedxSection.duel.fill)
                .disabled(!room.canStart)

                if !room.canStart {
                    Text("\(room.theirProfile?.displayName ?? "The other one") gets a Join button on "
                         + "their Home screen while this is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("You are in. Waiting for \(room.theirProfile?.displayName ?? "the host") to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func seat(profile: Profile?, isHere: Bool) -> some View {
        VStack(spacing: 6) {
            if isHere, let profile {
                MedxSticker(profile.sticker, size: 44, tilt: -8)
                Text(profile.displayName)
                    .font(.subheadline.weight(.bold))
                Text(profile.tag)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("?")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("waiting")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("not in yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background {
            let shape = RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous)
            if isHere {
                shape.fill((profile?.duelSoft) ?? MedxSurface.cardFill)
            } else {
                shape.strokeBorder(
                    MedxSurface.separator,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
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
        VStack(alignment: .leading, spacing: 12) {
            if let first = firstProfile {
                HStack(spacing: 6) {
                    Image(systemName: "hare.fill")
                        .font(.caption.weight(.bold))
                    Text("\(first.displayName) was first in")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(first.duelFill)
            }

            VStack(spacing: 6) {
                line(profile: room.myProfile, answer: room.shownMine)
                line(profile: room.theirProfile, answer: room.shownTheirs)
            }

            if let question = room.question, !question.explanation.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    HTMLRichTextView(html: question.explanation, fontSize: 15, weight: .regular)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .medxCard()
            }

            if let question = room.question, !question.reference.isEmpty {
                Text(question.reference)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
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

        return HStack(spacing: 10) {
            Text(profile?.displayName ?? "—")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(profile?.duelFill ?? .secondary)
                .frame(minWidth: 62, alignment: .leading)

            Text(pickText(answer: answer, label: label))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            Text(sumText(answer: answer, points: points))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(points > 0 ? MedxTheme.successGreen : .secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background((profile?.duelSoft) ?? MedxSurface.tileFill, in: RoundedRectangle(cornerRadius: MedxSurface.tileRadius, style: .continuous))
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
