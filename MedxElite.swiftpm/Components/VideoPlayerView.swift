import SwiftUI
import AVKit

/// Native iOS video playback surface backed by AVPlayer and the system AVPlayerViewController controls.
public struct VideoPlayerView: View {
    public let video: RecordedVideo?
    public let streamUrl: String
    public let title: String
    public let subtitle: String?
    public var onDismiss: (() -> Void)?

    @StateObject private var proxy = HLSProxyServer.shared
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage = ""
    @State private var timeObserverToken: Any?
    @State private var showResumeToast = false
    @State private var resumedFromSeconds: Double = 0
    @State private var lastCloudSyncTime: Date = Date()
    @State private var usingOfflineCopy = false
    @State private var forceOnlinePlayback = false
    @State private var showOfflineBadge = false
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss

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

                if showOfflineBadge {
                    VStack {
                        HStack {
                            offlineBadgeView
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(.top, 18)
                    .padding(.leading, 20)
                    .transition(.opacity)
                    .zIndex(9)
                }

                if showResumeToast {
                    VStack {
                        resumeToastView
                            .padding(.top, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .zIndex(10)
                }
            } else {
                loadingView
            }
        }
        .onAppear {
            setupProxyAndPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
        .statusBarHidden(true)
        .background(Color.black)
    }

    private var offlineBadgeView: some View {
        Label("Playing your download", systemImage: "arrow.down.circle.fill")
            .font(MedxFont.label(11))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(MedxTheme.successGreen.opacity(0.45), lineWidth: 1))
            .accessibilityLabel("Playing the offline download")
    }

    private var resumeToastView: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(MedxTheme.cyanAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Resumed Playback")
                    .font(MedxFont.headline(13))
                    .foregroundColor(.white)
                Text("Playing from \(formatTime(resumedFromSeconds))")
                    .font(MedxFont.caption(11))
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer(minLength: 8)

            Button {
                HapticManager.selection()
                restartFromBeginning()
            } label: {
                Text("Start Over")
                    .font(MedxFont.label(12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.2), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Restart video from beginning")

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    showResumeToast = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss resume notification")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MedxTheme.cyanAccent.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 24)
    }

    private var loadingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)

            Text("Loading video stream…")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading video")
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Playback Error")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
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
                .tint(.white)
                .foregroundStyle(.black)

                Button("Close") {
                    closePlayer()
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .frame(maxWidth: 320)
        }
        .padding(24)
    }

    private func setupProxyAndPlayer() {
        isLoading = true
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

        if proxy.isRunning == false {
            proxy.start()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            createPlayer()
        }
    }

    private func createPlayer() {
        let playbackURL: URL?
        var isOffline = false

        if !forceOnlinePlayback,
           let video,
           let offlineURL = VideoDownloadStore.offlinePlaylistURL(for: video.id) {
            playbackURL = offlineURL
            isOffline = true
            print("[VideoPlayer] Using offline download")
        } else if let proxied = proxy.proxiedURL(for: streamUrl) {
            playbackURL = proxied
            print("[VideoPlayer] Using proxied URL on port \(proxy.port)")
        } else if let direct = URL(string: streamUrl) {
            playbackURL = direct
            print("[VideoPlayer] Proxy unavailable, using direct URL")
        } else {
            hasError = true
            errorMessage = "Invalid stream URL"
            isLoading = false
            return
        }

        guard let url = playbackURL else { return }

        usingOfflineCopy = isOffline

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        player.preventsDisplaySleepDuringVideoPlayback = true

        if let video, let history = activityStore.entry(for: video.id, uid: authService.currentSession?.uid), history.resumePosition > 5 {
            let targetSeconds = history.resumePosition
            player.seek(to: CMTime(seconds: targetSeconds, preferredTimescale: 600))
            self.resumedFromSeconds = targetSeconds
            withAnimation(.easeOut(duration: 0.35)) {
                self.showResumeToast = true
            }
            // Auto dismiss toast after 4.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                withAnimation(.easeOut(duration: 0.35)) {
                    self.showResumeToast = false
                }
            }
        }

        player.playImmediately(atRate: 1.0)

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main) { time in
            guard let video = self.video else { return }
            let duration = player.currentItem?.duration.seconds ?? Double(video.durationSeconds ?? 0)
            let currentSecs = time.seconds
            guard currentSecs.isFinite, currentSecs >= 0 else { return }

            let shouldSyncCloud = Date().timeIntervalSince(self.lastCloudSyncTime) >= 20.0
            if shouldSyncCloud {
                self.lastCloudSyncTime = Date()
            }

            Task { @MainActor in
                ActivityStore.shared.recordVideoProgress(
                    video: video,
                    uid: self.authService.currentSession?.uid,
                    position: currentSecs,
                    duration: duration.isFinite ? duration : 0,
                    syncToCloud: shouldSyncCloud
                )
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { notification in
            if self.usingOfflineCopy {
                self.fallBackToOnlinePlayback()
                return
            }
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                self.hasError = true
                self.errorMessage = error.localizedDescription
            }
        }

        self.player = player
        isLoading = false

        if isOffline {
            withAnimation(.easeOut(duration: 0.3)) {
                showOfflineBadge = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.showOfflineBadge = false
                }
            }
            // A rewritten local playlist can still be rejected by AVFoundation, so give it
            // a few seconds and quietly fall back to streaming instead of dead-ending.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                guard self.usingOfflineCopy, let current = self.player?.currentItem else { return }
                if current.status == .failed {
                    self.fallBackToOnlinePlayback()
                }
            }
        }
    }

    /// Swaps a failed offline copy for the live stream without touching saved progress.
    private func fallBackToOnlinePlayback() {
        guard usingOfflineCopy else { return }
        print("[VideoPlayer] Offline copy unplayable, falling back to the stream")
        usingOfflineCopy = false
        forceOnlinePlayback = true
        showOfflineBadge = false

        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        if proxy.isRunning == false {
            proxy.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            createPlayer()
        }
    }

    private func restartFromBeginning() {
        guard let player else { return }
        player.seek(to: .zero)
        withAnimation(.easeOut(duration: 0.25)) {
            showResumeToast = false
        }
        if let video {
            let duration = player.currentItem?.duration.seconds ?? Double(video.durationSeconds ?? 0)
            ActivityStore.shared.recordVideoProgress(
                video: video,
                uid: authService.currentSession?.uid,
                position: 0,
                duration: duration.isFinite ? duration : 0,
                syncToCloud: true
            )
        }
    }

    private func teardownPlayer() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        if let video, let player {
            let duration = player.currentItem?.duration.seconds ?? Double(video.durationSeconds ?? 0)
            let position = player.currentTime().seconds
            if position.isFinite, position >= 0 {
                ActivityStore.shared.recordVideoProgress(
                    video: video,
                    uid: authService.currentSession?.uid,
                    position: position,
                    duration: duration.isFinite ? duration : 0,
                    syncToCloud: true
                )
            }
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func closePlayer() {
        player?.pause()
        if let dismissHandler = onDismiss {
            dismissHandler()
        } else {
            dismiss()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Native AVPlayerViewController Wrapper

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
        uiViewController.player = player
        uiViewController.allowsPictureInPicturePlayback = AVPictureInPictureController.isPictureInPictureSupported()
        uiViewController.canStartPictureInPictureAutomaticallyFromInline = AVPictureInPictureController.isPictureInPictureSupported()
    }
}
