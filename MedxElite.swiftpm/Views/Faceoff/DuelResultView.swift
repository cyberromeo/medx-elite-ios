import SwiftUI

/// The finish, and what a re-opened finished room shows: a grouped list like the sitting review.
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

    private var headlineText: String {
        guard let winner else { return "Dead heat" }
        return iWon ? "You took it" : "\(winner.displayName) took it"
    }

    /// The one line that puts a score in context: 1,284 out of a possible 2,000 says more than
    /// 1,284 ever could.
    private var outOfLine: String {
        "\(MedxFormat.count(room.myScore.points)) of "
            + "\(MedxFormat.count(MedxDuelRules.possiblePoints(max(room.total, log.count)))) possible"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: MedxSpace.l) {
                    HStack(spacing: MedxSpace.m) {
                        MedxSymbolTile(
                            winner == nil ? "equal" : (iWon ? "trophy.fill" : "medal.fill"),
                            hue: winner?.duelTint ?? MedxOutcome.pending,
                            size: 44
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(headlineText)
                                .font(.title2.weight(.bold))
                            Text(outOfLine)
                                .font(.footnote)
                                .monospacedDigit()
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
                .padding(.vertical, MedxSpace.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(headlineText)
                .accessibilityValue(outOfLine)
            }

            Section("Side by side") {
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
                    mine: room.myScore.fastest.map { "\($0)s" } ?? "-",
                    theirs: room.theirScore.fastest.map { "\($0)s" } ?? "-"
                )
            }

            Section("Round by round") {
                ForEach(log, id: \.qIndex) { row in
                    reviewRow(row)
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    HapticManager.light()
                    onDone()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            if winner == nil { HapticManager.selection() } else if iWon { HapticManager.success() }
        }
    }

    // MARK: - Rows

    private func statRow(label: String, mine: String, theirs: String) -> some View {
        HStack(spacing: MedxSpace.m) {
            Text(mine)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(room.myProfile?.duelTint ?? Color.primary)
                .frame(minWidth: 54, alignment: .leading)

            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Text(theirs)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(room.theirProfile?.duelTint ?? Color.primary)
                .frame(minWidth: 54, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(room.myProfile?.displayName ?? "you") \(mine), "
                            + "\(room.theirProfile?.displayName ?? "them") \(theirs)")
    }

    private func reviewRow(_ row: MedxDuelLogRow) -> some View {
        let myUid = AuthService.shared.currentSession?.uid ?? ""
        let theirUid = room.theirs?.uid ?? room.uids.first { $0 != myUid } ?? ""
        let mine = row.answers[myUid]
        let theirs = row.answers[theirUid]

        return HStack(spacing: MedxSpace.m) {
            Text("\(row.qIndex + 1)")
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(minWidth: 22, alignment: .trailing)

            mark(mine)
            Text("\(mine?.points ?? 0)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(room.myProfile?.duelTint ?? Color.primary)
                .frame(minWidth: 28, alignment: .leading)

            Spacer(minLength: MedxSpace.xs)

            if row.winner == nil {
                Text("even")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if row.winner == myUid {
                Text("you")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(room.myProfile?.duelTint ?? Color.primary)
            } else {
                Text(room.theirProfile?.displayName ?? "them")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(room.theirProfile?.duelTint ?? Color.primary)
            }

            Spacer(minLength: MedxSpace.xs)

            Text("\(theirs?.points ?? 0)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(room.theirProfile?.duelTint ?? Color.primary)
                .frame(minWidth: 28, alignment: .trailing)
            mark(theirs)
        }
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
            tint = MedxOutcome.correct
        } else if answer?.timedOut ?? true {
            symbol = "clock.badge.xmark"
            tint = MedxOutcome.pending
        } else {
            symbol = "xmark.circle.fill"
            tint = MedxOutcome.wrong
        }
        return Image(systemName: symbol)
            .font(.footnote.weight(.bold))
            .foregroundStyle(tint)
    }
}
