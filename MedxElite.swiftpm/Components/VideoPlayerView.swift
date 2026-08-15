import SwiftUI
import AVKit

public struct VideoPlayerView: View {
    public let streamUrl: String
    public let title: String
    public let subtitle: String?

    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var selectedSpeed: Float = 1.0
    @State private var showControls = true
    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    public init(streamUrl: String, title: String, subtitle: String? = nil) {
        self.streamUrl = streamUrl
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let p = player {
                CustomVideoPlayerController(player: p)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func setupPlayer() {
        guard let url = URL(string: streamUrl) else { return }
        
        // Setup audio session for continuous playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let p = AVPlayer(url: url)
        p.playImmediately(atRate: selectedSpeed)
        self.player = p
    }
}

struct CustomVideoPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
