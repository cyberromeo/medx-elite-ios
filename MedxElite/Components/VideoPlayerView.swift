import SwiftUI
import AVKit

/// Native playback surface backed by `AVPlayer` and the system `AVPlayerViewController`
/// controls. Resume is silent: the player simply starts where the student left off, with
/// no toast to dismiss — the scrubber already says where you are.
public struct VideoPlayerView: View {
    public let video: RecordedVideo?
    public let streamUrl: String
    public let title: String
    public let subtitle: String?
    public var onDismiss: (() -> Void)?

    @StateObject private var proxy = HLSProxyServer.shared
    @State private var player: AVPlayer?
    @State private var hasError = false
    @State private var errorMessage = ""
    @State private var timeObserverToken: Any?
    @State private var failureObserver: NSObjectProtocol?
    @State private var lastCloudSyncTime = Date.distantPast
    @State private var usingOfflineCopy = false
    @State private var forceOnlinePlayback = false
    @State private var showOfflineBadge = false
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    public init(
        streamUrl: String,
        title: String,
        subtitle: String? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.streamUrl = streamUrl
        self.title = title
        self.subtitle = subtitle
        self.onDismiss = onDismiss
        self.video = nil
    }

    public init(video: RecordedVideo, onDismiss: (() -> Void)? = nil) {
        self.video = video
        self.streamUrl = video.streamUrl
        self.title = video.title
        self.subtitle = video.faculty
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if hasError {
                errorView
            } else if let currentPlayer = player {
                ProxiedVideoPlayerController(player: currentPlayer)
                    .ignoresSafeArea()
            } else {
                loadingView
            }
        }
        .overlay(alignment: .topLeading) {
            if showOfflineBadge {
                offlineBadge
                    .padding(.leading, 18)
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .onAppear { setupProxyAndPlayer() }
        .onDisappear { teardownPlayer() }
        .onChange(of: scenePhase) { _, phase in
            // Playback continues in the background (audio is a declared background mode),
            // so the position is checkpointed on the way out rather than lost.
            if phase != .active { recordProgress(syncToCloud: true) }
        }
        .statusBarHidden(true)
        .background(Color.black)
    }

    // MARK: - Overlays

    private var offlineBadge: some View {
        Label("Playing your download", systemImage: "arrow.down.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityLabel("Playing the offline download")
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Loading video…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading video")
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(MedxTheme.warningOrange)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Playback Error")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                Button {
                    HapticManager.light()
                    hasError = false
                    setupProxyAndPlayer()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.white)
                .foregroundStyle(.black)

                Button("Close") { closePlayer() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.white)
            }
            .frame(maxWidth: 320)
        }
        .padding(24)
    }

    // MARK: - Setup

    @MainActor
    private func setupProxyAndPlayer() {
        hasError = false

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[VideoPlayer] Audio session error: \(error)")
        }

        // `waitUntilRunning` starts the listener and waits for the port to be bound
        // instead of guessing at a delay: without a port there is no offline URL, and the
        // download would look broken.
        Task { @MainActor in
            _ = await proxy.waitUntilRunning()
            createPlayer()
        }
    }

    @MainActor
    private func createPlayer() {
        guard let url = resolvePlaybackURL() else { return }

        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.allowsExternalPlayback = true
        newPlayer.preventsDisplaySleepDuringVideoPlayback = true
        newPlayer.automaticallyWaitsToMinimizeStalling = true

        // Silent resume. AVPlayer queues a seek issued before the item is ready and
        // applies it once it is, so no readiness dance is needed here.
        if let video,
           let history = activityStore.entry(for: video.id, uid: authService.currentSession?.uid),
           history.resumePosition > 5 {
            newPlayer.seek(
                to: CMTime(seconds: history.resumePosition, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
            )
        }

        newPlayer.playImmediately(atRate: 1.0)
        installObservers(on: newPlayer, item: item)

        player = newPlayer

        guard usingOfflineCopy else { return }
        withAnimation(.easeOut(duration: 0.25)) { showOfflineBadge = true }

        // `Task` rather than `DispatchQueue.asyncAfter`: that block is `@Sendable`, so it
        // does not inherit the main actor and cannot touch this view's state.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.25)) { showOfflineBadge = false }
        }

        // A rewritten local playlist can still be rejected by AVFoundation, so give it a
        // few seconds and quietly fall back to streaming instead of dead-ending.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard usingOfflineCopy, player?.currentItem?.status == .failed else { return }
            fallBackToOnlinePlayback()
        }
    }

    @MainActor
    private func resolvePlaybackURL() -> URL? {
        let hasDownload = video.map {
            VideoDownloadStore.shared.isDownloaded($0.id) || VideoDownloadStore.hasOfflineCopy($0.id)
        } ?? false

        if !forceOnlinePlayback,
           let video,
           hasDownload,
           let offlineURL = proxy.offlineURL(videoId: video.id) {
            // AVFoundation cannot load an HLS playlist from `file://`, so the saved
            // playlist is served over the loopback proxy. No network is involved.
            usingOfflineCopy = true
            return offlineURL
        }

        usingOfflineCopy = false

        if let proxied = proxy.proxiedURL(for: streamUrl) { return proxied }
        if let direct = URL(string: streamUrl) { return direct }

        hasError = true
        errorMessage = "This class has no valid stream URL."
        return nil
    }

    // MARK: - Observers

    @MainActor
    private func installObservers(on newPlayer: AVPlayer, item: AVPlayerItem) {
        // Both blocks are delivered on `.main` but are not *typed* as main-actor isolated,
        // so the work hops onto the actor explicitly rather than touching `@State` and the
        // main-actor `ActivityStore` from a nonisolated closure.
        timeObserverToken = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600),
            queue: .main
        ) { _ in
            Task { @MainActor in
                // Every 20s the position also goes to Firestore. Offline playback marks the
                // entry pending instead, and `ActivityStore` retries it on the next sync —
                // so a class watched from its download still lands on the streaming row.
                let shouldSync = Date().timeIntervalSince(self.lastCloudSyncTime) >= 20
                if shouldSync { self.lastCloudSyncTime = Date() }
                self.recordProgress(syncToCloud: shouldSync)
            }
        }

        // The old code registered this observer on every player it built and never removed
        // one, so a fall-back to streaming left two live observers behind.
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { notification in
            let failure = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in
                if self.usingOfflineCopy {
                    self.fallBackToOnlinePlayback()
                    return
                }
                if let failure {
                    self.hasError = true
                    self.errorMessage = failure.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func removeObservers() {
        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil

        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        failureObserver = nil
    }

    // MARK: - Progress

    @MainActor
    private func recordProgress(syncToCloud: Bool) {
        guard let video, let player else { return }
        let position = player.currentTime().seconds
        guard position.isFinite, position >= 0 else { return }

        let duration = player.currentItem?.duration.seconds ?? Double(video.durationSeconds ?? 0)

        ActivityStore.shared.recordVideoProgress(
            video: video,
            uid: authService.currentSession?.uid,
            position: position,
            duration: duration.isFinite ? duration : 0,
            syncToCloud: syncToCloud
        )
    }

    /// Swaps a failed offline copy for the live stream without touching saved progress.
    @MainActor
    private func fallBackToOnlinePlayback() {
        guard usingOfflineCopy else { return }
        print("[VideoPlayer] Offline copy unplayable, falling back to the stream")
        usingOfflineCopy = false
        forceOnlinePlayback = true
        showOfflineBadge = false

        removeObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        Task { @MainActor in
            _ = await proxy.waitUntilRunning()
            createPlayer()
        }
    }

    @MainActor
    private func teardownPlayer() {
        recordProgress(syncToCloud: true)
        removeObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    @MainActor
    private func closePlayer() {
        player?.pause()
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}

// MARK: - Native AVPlayerViewController wrapper

struct ProxiedVideoPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = AVPictureInPictureController.isPictureInPictureSupported()
        controller.canStartPictureInPictureAutomaticallyFromInline = AVPictureInPictureController.isPictureInPictureSupported()
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        controller.updatesNowPlayingInfoCenter = true
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
