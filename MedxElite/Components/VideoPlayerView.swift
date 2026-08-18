import SwiftUI
import AVKit

/// Native iOS video playback surface backed by AVPlayer and the system AVPlayerViewController controls.
public struct VideoPlayerView: View {
    public let streamUrl: String
    public let title: String
    public let subtitle: String?
    public var onDismiss: (() -> Void)?

    @StateObject private var proxy = HLSProxyServer.shared
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage = ""
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
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if hasError {
                errorView
            } else if let player {
                ProxiedVideoPlayerController(player: player)
                    .ignoresSafeArea()
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

        if !proxy.isRunning {
            proxy.start()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            createPlayer()
        }
    }

    private func createPlayer() {
        let playbackURL: URL?
        if let proxied = proxy.proxiedURL(for: streamUrl) {
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

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.playImmediately(atRate: 1.0)

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                self.hasError = true
                self.errorMessage = error.localizedDescription
            }
        }

        self.player = player
        isLoading = false
    }

    private func teardownPlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func closePlayer() {
        player?.pause()
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
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
        controller.allowsPictureInPicturePlayback = AVPictureInPictureController.isPictureInPictureSupported
        controller.canStartPictureInPictureAutomaticallyFromInline = AVPictureInPictureController.isPictureInPictureSupported
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        controller.updatesNowPlayingInfoCenter = true
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        uiViewController.allowsPictureInPicturePlayback = AVPictureInPictureController.isPictureInPictureSupported
        uiViewController.canStartPictureInPictureAutomaticallyFromInline = AVPictureInPictureController.isPictureInPictureSupported
    }
}
