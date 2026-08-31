import SwiftUI

/// The launch experience: the mark draws itself, the wordmark fades up, and the whole
/// thing hands over to the real root.
///
/// It is an *overlay* over the live app rather than a gate in front of it — the first data
/// task is already running underneath, so the splash never adds waiting time. It leaves as
/// soon as both the minimum on-screen time and the bootstrap have finished.
public struct MedxSplashView: View {
    @State private var trim: CGFloat = 0
    @State private var started = false
    @State private var wordmarkVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private let markSize: CGFloat = 116

    public var body: some View {
        ZStack {
            MedxInk.page
                .ignoresSafeArea()

            VStack(spacing: 26) {
                mark

                VStack(spacing: 9) {
                    MedxWordmark(size: 26)

                    // The eyebrow shape from every page header in the app, used once here so the
                    // launch reads as the same product as the screen behind it. The mark itself is
                    // untouched: it shares its coordinates with the app icon.
                    Text("ARISE · MARROW · FACEOFF")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(MedxSection.home.onSoft)
                }
                .opacity(wordmarkVisible ? 1 : 0)
                .offset(y: wordmarkVisible ? 0 : 10)
            }
        }
        .task {
            guard !reduceMotion else {
                trim = 1
                wordmarkVisible = true
                return
            }
            withAnimation(.easeOut(duration: 0.62)) { trim = 1 }
            started = true
            try? await Task.sleep(nanoseconds: 260_000_000)
            withAnimation(.smooth(duration: 0.42)) { wordmarkVisible = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MedX Elite is starting")
    }

    @ViewBuilder
    private var mark: some View {
        if reduceMotion {
            MedxLogoMark(size: markSize, trim: 1)
        } else {
            MedxLogoMark(size: markSize, trim: trim)
                .phaseAnimator(MedxSplashPhase.allCases, trigger: started) { content, phase in
                    content
                        .scaleEffect(phase.scale)
                        .opacity(phase.opacity)
                } animation: { phase in
                    phase.animation
                }
        }
    }
}

/// Three beats: arrive small and dim, overshoot very slightly as the trace completes, then
/// settle. Deliberately restrained — a launch screen that bounces reads as a toy.
enum MedxSplashPhase: CaseIterable {
    case arriving
    case overshoot
    case settled

    var scale: CGFloat {
        switch self {
        case .arriving: return 0.88
        case .overshoot: return 1.04
        case .settled: return 1
        }
    }

    var opacity: Double {
        switch self {
        case .arriving: return 0.35
        case .overshoot, .settled: return 1
        }
    }

    var animation: Animation? {
        switch self {
        case .arriving: return .easeOut(duration: 0.28)
        case .overshoot: return .spring(duration: 0.42, bounce: 0.28)
        case .settled: return .smooth(duration: 0.3)
        }
    }
}
