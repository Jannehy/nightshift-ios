import AVFoundation
import Foundation

/// Plays the 30-second iTunes previews. One track at a time.
@MainActor
final class PreviewPlayer: ObservableObject {
    @Published private(set) var currentURL: URL?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func isPlaying(_ url: URL?) -> Bool {
        guard let url, let currentURL else { return false }
        return url == currentURL
    }

    func toggle(_ url: URL?) {
        guard let url else { return }
        if currentURL == url {
            stop()
        } else {
            play(url)
        }
    }

    private func play(_ url: URL) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        self.player = player
        currentURL = url
        player.play()
    }

    func stop() {
        player?.pause()
        player = nil
        currentURL = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
