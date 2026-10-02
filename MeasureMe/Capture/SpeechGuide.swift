import AVFoundation

/// Speaks capture instructions so a person standing away from the phone can follow along.
@MainActor
final class SpeechGuide {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastMessage: String?
    private var lastSpokenAt = Date.distantPast
    var isEnabled = true

    func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func deactivateAudioSession() {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Speaks `text` unless the same message was spoken recently. `force` interrupts current speech.
    func say(_ text: String, force: Bool = false, repeatAfter: TimeInterval = 5) {
        guard isEnabled else { return }
        let now = Date()
        if !force {
            if synthesizer.isSpeaking { return }
            if text == lastMessage && now.timeIntervalSince(lastSpokenAt) < repeatAfter { return }
        } else {
            synthesizer.stopSpeaking(at: .immediate)
        }
        lastMessage = text
        lastSpokenAt = now
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
