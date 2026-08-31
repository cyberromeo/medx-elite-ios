import SwiftUI

/// The finish, and what a re-opened finished room shows.
///
/// Everything here is derived from the game's log rather than from the `scores` field the host
/// wrote, so the headline, the per-side stats and the round-by-round review cannot disagree with
/// each other — and a game whose final write half-landed still reads correctly.
struct DuelResultView: View {
    @ObservedObject var room: MedxDuelRoom
    let onDone: () -> Void

    private var log: [MedxDuelLogRow] { room.game?.log ?? [] }

    private var winner: Profile? {
        MedxDuelRules.leader(scores: room.scores, uids: room.uids).flatMap { Profile.byUid($0) }
    }

    private var iWon: Bool {
        winner?.uid == AuthService.shared.currentSession?.uid
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headline

                    MedxVersusBar(
                        mine: room.myScore,
                        theirs: room.theirScore,
                        myProfile: room.myProfile,
                        theirProfile: room.theirProfile
                    )

                    outOf
                    statsGrid
                    review
                }
                .padding(.horizontal, MedxDS.gutter)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }

            Button {
                HapticManager.light()
                onDone()
            } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .medxFilled(MedxSection.duel.fill)
            .medxFloatingBar()
        }
        .onAppear {
            if winner == nil { HapticManager.selection() } else if iWon { HapticManager.success() }
        }
    }

    // MARK: - Pieces

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                MedxSticker(winner == nil ? "hourglass" : (iWon ? "trophy" : "medal"), size: 44, tilt: -8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.source?.name ?? "Faceoff")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(MedxSection.duel.onSoft)

                    Text(headlineText)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var headlineText: String {
        guard let winner else { return "Dead heat" }
        return iWon ? "You took it" : "\(winner.displayName) took it"
    }

    /// The one line that puts a score in context: 1,284 out of a possible 2,000 says more than
    /// 1,284 ever could.
    private var outOf: some View {
        Text("\(room.myScore.points.formatted()) of "
             + "\(MedxDuelRules.possiblePoints(max(room.total, log.count)).formatted()) possible")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader("Side by side")

            VStack(spacing: 8) {
                statRow(
                    label: "Right",
                    mine: "\(room.myScore.correct)/\(room.myScore.rounds)",
                    theirs: "\(room.theirScore.correct)/\(room.theirScore.rounds)"
                )
                statRow(
                    label: "Answered",
                    mine: "\(room.myScore.answered)",
                    theirs: "\(room.theirScore.answered)"
                )
                statRow(
                    label: "First in",
                    mine: "\(room.myScore.firsts)",
                    theirs: "\(room.theirScore.firsts)"
                )
                statRow(
                    label: "Fastest right",
                    mine: room.myScore.fastest.map { "\($0)s" } ?? "—",
                    theirs: room.theirScore.fastest.map { "\($0)s" } ?? "—"
                )
            }
        }
    }

    private func statRow(label: String, mine: String, theirs: String) -> some View {
        HStack(spacing: 10) {
            Text(mine)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(room.myProfile?.duelFill ?? .primary)
                .frame(minWidth: 54, alignment: .leading)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Text(theirs)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(room.theirProfile?.duelFill ?? .primary)
                .frame(minWidth: 54, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .medxTile()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(room.myProfile?.displayName ?? "you") \(mine), "
                            + "\(room.theirProfile?.displayName ?? "them") \(theirs)")
    }

    // MARK: - Round by round

    private var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader("Round by round")

            VStack(spacing: 6) {
                ForEach(log, id: \.qIndex) { row in
                    reviewRow(row)
                }
            }
        }
    }

    private func reviewRow(_ row: MedxDuelLogRow) -> some View {
        let myUid = AuthService.shared.currentSession?.uid ?? ""
        let theirUid = room.theirs?.uid ?? room.uids.first { $0 != myUid } ?? ""
        let mine = row.answers[myUid]
        let theirs = row.answers[theirUid]

        return HStack(spacing: 10) {
            Text("\(row.qIndex + 1)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 22, alignment: .trailing)

            mark(mine)
            Text("\(mine?.points ?? 0)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(room.myProfile?.duelFill ?? .primary)
                .frame(minWidth: 28, alignment: .leading)

            Spacer(minLength: 4)

            if row.winner == nil {
                Text("even")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if row.winner == myUid {
                Text("you")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(room.myProfile?.duelFill ?? .primary)
            } else {
                Text(room.theirProfile?.displayName ?? "them")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(room.theirProfile?.duelFill ?? .primary)
            }

            Spacer(minLength: 4)

            Text("\(theirs?.points ?? 0)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(room.theirProfile?.duelFill ?? .primary)
                .frame(minWidth: 28, alignment: .trailing)
            mark(theirs)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .medxTile()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Question \(row.qIndex + 1)")
        .accessibilityValue("you \(mine?.points ?? 0), them \(theirs?.points ?? 0)")
    }

    /// Right, wrong, or never answered — three states, because "wrong" and "ran out of clock" are
    /// different mistakes and the review is the only place that distinction survives.
    private func mark(_ answer: MedxDuelAnswerRow?) -> some View {
        let symbol: String
        let tint: Color
        if answer?.correct == true {
            symbol = "checkmark.circle.fill"
            tint = MedxDS.correct
        } else if answer?.timedOut ?? true {
            symbol = "clock.badge.xmark"
            tint = .secondary
        } else {
            symbol = "xmark.circle.fill"
            tint = MedxDS.wrong
        }
        return Image(systemName: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
    }
}
