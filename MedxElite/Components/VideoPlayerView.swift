import SwiftUI
import AVKit

/// Full-screen video playback with the native AVPlayer controls and a small,
/// safe-area-aware header for dismissal, title context, speed, and AirPlay.
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
            Color.black.ignoresSafeArea()

            if hasError {
                errorView
            } else if let p = player {
                ProxiedVideoPlayerController(player: p)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    playerHeader
                    Spacer(minLength: 0)
                }
                .zIndex(2)
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
    }

    // MARK: - Native Player Header

    private var playerHeader: some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.light()
                closePlayer()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.16), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close video")
            .accessibilityHint("Dismisses the video player")

            VStack(alignment: .leading, spacing: 3) {
                Text("NOW PLAYING")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.68))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Menu {
                Section("Playback Speed") {
                    ForEach(speeds, id: \.self) { speed in
                        Button {
                            selectedSpeed = speed
                            player?.rate = speed
                            HapticManager.selection()
                        } label: {
                            Label {
                                Text(speedLabel(speed))
                            } icon: {
                                if speed == selectedSpeed {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Label(speedLabel(selectedSpeed), systemImage: "gauge.with.dots.needle.50percent")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed")
            .accessibilityValue(speedLabel(selectedSpeed))

            AirPlayButton()
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.16), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8))
                .accessibilityLabel("AirPlay")
                .accessibilityHint("Choose an AirPlay playback destination")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.94),
                    Color.black.opacity(0.72),
                    Color.black.opacity(0.18),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(height: 0.5)
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                Text("Loading video stream…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading \(title)")
    }

    // MARK: - Error State

    private var errorView: some View {
        VStack(spacing: 24) {
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
                    .padding(.horizontal, 20)
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

    // MARK: - Setup & Playback

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

        player = p
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
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
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
        picker.tintColor = .label
        picker.activeTintColor = UIColor(MedxTheme.primaryBlue)
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
