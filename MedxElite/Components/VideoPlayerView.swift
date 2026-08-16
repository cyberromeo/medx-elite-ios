import SwiftUI
import AVKit

/// Modern iOS video player with HLS proxy integration for header spoofing.
/// Features: PiP, AirPlay, speed control, background audio, error recovery.
public struct VideoPlayerView: View {
    public let streamUrl: String
    public let title: String
    public let subtitle: String?

    @StateObject private var proxy = HLSProxyServer.shared
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage = ""
    @State private var selectedSpeed: Float = 1.0
    @State private var showSpeedPicker = false
    @State private var showInfo = true
    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    public init(streamUrl: String, title: String, subtitle: String? = nil) {
        self.streamUrl = streamUrl
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            if hasError {
                errorView
            } else if let p = player {
                // Native AVPlayerViewController
                ProxiedVideoPlayerController(player: p)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showInfo.toggle()
                        }
                    }

                // Overlay controls
                if showInfo {
                    overlayControls
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
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if isLoading {
                    Text("Connecting to stream…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(40)
    }

    // MARK: - Error State

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
                .symbolEffect(.pulse)

            VStack(spacing: 8) {
                Text("Playback Error")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Button {
                hasError = false
                setupProxyAndPlayer()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(.white, in: Capsule())
            }
        }
        .padding(40)
    }

    // MARK: - Overlay Controls

    private var overlayControls: some View {
        VStack {
            // Top bar
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if let sub = subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                // Speed picker
                Menu {
                    ForEach(speeds, id: \.self) { speed in
                        Button {
                            selectedSpeed = speed
                            player?.rate = speed
                            HapticManager.selection()
                        } label: {
                            HStack {
                                Text(speedLabel(speed))
                                if speed == selectedSpeed {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(speedLabel(selectedSpeed))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                // AirPlay
                AirPlayButton()
                    .frame(width: 36, height: 36)
                    .tint(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )

            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Setup

    private func setupProxyAndPlayer() {
        isLoading = true
        hasError = false

        // Setup audio session for background + AirPlay
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[VideoPlayer] Audio session error: \(error)")
        }

        // Start the HLS proxy if not running
        if !proxy.isRunning {
            proxy.start()
        }

        // Wait a moment for the proxy to bind, then create the player
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            createPlayer()
        }
    }

    private func createPlayer() {
        // Try proxied URL first, fall back to direct
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

        // Observe player item status for error handling
        let p = AVPlayer(playerItem: item)
        p.allowsExternalPlayback = true
        p.preventsDisplaySleepDuringVideoPlayback = true
        p.playImmediately(atRate: selectedSpeed)

        // Watch for failures
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

        self.player = p
        self.isLoading = false
    }

    private func teardownPlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func speedLabel(_ speed: Float) -> String {
        if speed == Float(Int(speed)) {
            return "\(Int(speed))×"
        }
        return String(format: "%.2g×", speed)
    }
}

// MARK: - Native AVPlayerViewController Wrapper

struct ProxiedVideoPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        controller.updatesNowPlayingInfoCenter = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

// MARK: - AirPlay Button

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .systemBlue
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
