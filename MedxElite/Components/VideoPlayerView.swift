import SwiftUI
import AVKit

/// Modern, immersive iOS video player with HLS proxy integration for header spoofing.
/// Features: PiP, AirPlay, speed control menu, background playback, and non-intrusive floating glass controls.
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
    @State private var selectedSpeed: Float = 1.0
    @State private var showControls = true
    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

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
            // Immersive black canvas
            Color.black.ignoresSafeArea()

            if hasError {
                errorView
            } else if let p = player {
                // Native AVPlayerViewController
                ProxiedVideoPlayerController(player: p)
                    .ignoresSafeArea()

                // Floating glass top bar
                if showControls {
                    VStack {
                        floatingTopBar
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        Spacer()
                    }
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

    // MARK: - Floating Glass Top Bar

    private var floatingTopBar: some View {
        HStack(alignment: .center, spacing: 12) {
            // Dismiss Button
            Button {
                HapticManager.light()
                if let onDismiss = onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .buttonStyle(PlainButtonStyle())

            // Video Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MedxFont.headline(15))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let sub = subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(MedxFont.caption(12))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Speed Menu
            Menu {
                Section("Playback Speed") {
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
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.system(size: 11, weight: .semibold))
                    Text(speedLabel(selectedSpeed))
                        .font(MedxFont.mono(12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            }

            // AirPlay Button
            AirPlayButton()
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.3), radius: 16, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)

            VStack(spacing: 6) {
                Text(title)
                    .font(MedxFont.headline(16))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                Text("Loading video stream…")
                    .font(MedxFont.caption(13))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(40)
    }

    // MARK: - Error State

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
                .symbolEffect(.pulse)

            VStack(spacing: 8) {
                Text("Playback Error")
                    .font(MedxFont.title(18))
                    .foregroundColor(.white)

                Text(errorMessage)
                    .font(MedxFont.body(14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 16) {
                Button {
                    hasError = false
                    setupProxyAndPlayer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(MedxFont.headline(14))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
                }

                Button {
                    if let onDismiss = onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                } label: {
                    Text("Close")
                        .font(MedxFont.headline(14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }
        }
        .padding(40)
    }

    // MARK: - Setup & Playback

    private func setupProxyAndPlayer() {
        isLoading = true
        hasError = false

        // Configure audio session
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

        // Start proxy if needed
        if !proxy.isRunning {
            proxy.start()
        }

        // Initialize player
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

        let p = AVPlayer(playerItem: item)
        p.allowsExternalPlayback = true
        p.preventsDisplaySleepDuringVideoPlayback = true
        p.playImmediately(atRate: selectedSpeed)

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

// MARK: - AirPlay Route Picker

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(MedxTheme.primaryBlue)
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
