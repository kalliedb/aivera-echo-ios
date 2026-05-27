import AVFoundation
import Foundation

/// Plays a single recorded clip at a time. Switches the shared `AVAudioSession`
/// into `.playback` mode (the recogniser puts it into `.record`), then back to
/// inactive when playback ends. Mirrors Android's `AudioPlayer.kt`.
@MainActor
final class AudioPlayer: NSObject, ObservableObject {

    @Published private(set) var isPlaying = false
    @Published private(set) var nowPlayingURL: URL?

    private var player: AVAudioPlayer?

    /// Start playing the file at `url`. If something else is already playing,
    /// it's stopped first. No-op if the file doesn't exist.
    func play(url: URL) {
        stop()

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("AudioPlayer: file not found at \(url.lastPathComponent)")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            guard p.play() else {
                print("AudioPlayer: AVAudioPlayer.play() returned false")
                return
            }

            self.player = p
            self.nowPlayingURL = url
            self.isPlaying = true
        } catch {
            print("AudioPlayer.play failed: \(error)")
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        nowPlayingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Convenience for `String` paths stored in `Reminder.audioPath`.
    func play(path: String?) {
        guard let path, !path.isEmpty else { return }
        play(url: URL(fileURLWithPath: path))
    }
}

// MARK: - AVAudioPlayerDelegate (auto-stop at end of clip)
extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error { print("AudioPlayer decode error: \(error)") }
        Task { @MainActor in self.stop() }
    }
}
