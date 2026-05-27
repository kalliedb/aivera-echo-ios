import AVFoundation
import Combine
import Foundation
import Speech

/// On-device transcription via Apple Speech (free, no model bundle). The
/// equivalent of Android's `SpeechTranscriber.kt` (Vosk). One `AVAudioEngine`
/// feeds both the recogniser and a WAV file writer so we get the transcribed
/// text AND a playable audio clip from a single mic session.
@MainActor
final class SpeechRecognizer: ObservableObject {

    @Published private(set) var isRecording = false
    @Published private(set) var partialText = ""
    @Published private(set) var finalText = ""
    @Published private(set) var amplitude: Float = 0
    @Published private(set) var lastAudioURL: URL?
    @Published private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?

    var isAvailable: Bool {
        recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true
    }

    // MARK: - Permissions
    func requestPermissions() async -> Bool {
        let speechAuth = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechAuth == .authorized else { return false }

        let micAuth = await AVCaptureDevice.requestAccess(for: .audio)
        return micAuth
    }

    // MARK: - Recording
    func start() async throws {
        guard !isRecording else { return }
        guard isAvailable else { throw RecognizerError.unavailable }

        partialText = ""
        finalText = ""
        amplitude = 0
        errorMessage = nil

        // Configure audio session for record-only.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Prepare the WAV output file (we use the native input format and convert later if needed).
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        let dir = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileProtection.apply(to: dir)   // encrypt the audio folder + everything inside

        let url = dir.appendingPathComponent("echo_\(Int(Date().timeIntervalSince1970 * 1000)).caf")
        audioFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
        FileProtection.apply(to: url)   // belt + braces on the new clip file
        lastAudioURL = url

        // Build recognition request — on-device only, partial results on.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finalText = text
                    } else {
                        self.partialText = text
                    }
                }
                if error != nil {
                    self.stopInternal()
                }
            }
        }

        // Tap the input — push samples to both the recogniser and the file.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            request.append(buffer)
            try? self.audioFile?.write(from: buffer)
            // Cheap RMS amplitude for the waveform UI.
            if let channelData = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameCount { sum += channelData[i] * channelData[i] }
                let rms = sqrt(sum / Float(frameCount))
                Task { @MainActor in self.amplitude = min(1.0, rms * 6) }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        recognitionRequest?.endAudio()
        stopInternal()
    }

    /// Cancel without finalising — discards audio and any partial transcript.
    func cancel() {
        guard isRecording else { return }
        recognitionTask?.cancel()
        recognitionRequest = nil
        stopInternal()
        if let url = lastAudioURL { try? FileManager.default.removeItem(at: url) }
        lastAudioURL = nil
        partialText = ""
        finalText = ""
    }

    // MARK: - Internals
    private func stopInternal() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask = nil
        recognitionRequest = nil
        audioFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }

    enum RecognizerError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Voice recognition isn't available on this device."
            }
        }
    }
}
