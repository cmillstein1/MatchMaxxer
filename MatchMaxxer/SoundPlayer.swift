import AVFoundation
import UIKit

enum SoundCue {
    case ready    // A4
    case set      // C#5
    case go       // A5 (octave above ready) — completes the rising A-major-triad arpeggio
    case tick     // short high blip during countdown
    case lock     // E5 — fits the same A-major chord
    case scoreTick
}

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private let format: AVAudioFormat
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var started = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        configureSession()
        startEngineIfNeeded()
    }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.ambient, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    private func startEngineIfNeeded() {
        guard !started else { return }
        do {
            try engine.start()
            player.play()
            started = true
        } catch {
            started = false
        }
    }

    static func play(_ cue: SoundCue) {
        shared.play(cue)
    }

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    private func play(_ cue: SoundCue) {
        startEngineIfNeeded()
        guard started else { return }
        let buffer = bufferForCue(cue)
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
    }

    private func bufferForCue(_ cue: SoundCue) -> AVAudioPCMBuffer {
        let key = "\(cue)"
        if let cached = buffers[key] { return cached }
        let (freq, duration, gain): (Double, Double, Double) = {
            switch cue {
            case .ready:     return (440.0,  0.130, 0.55)
            case .set:       return (554.37, 0.130, 0.55)
            case .go:        return (880.0,  0.260, 0.65)
            case .tick:      return (1320.0, 0.028, 0.32)
            case .lock:      return (659.25, 0.110, 0.60)
            case .scoreTick: return (1046.5, 0.022, 0.28)
            }
        }()
        let buf = makeToneBuffer(frequency: freq, duration: duration, gain: gain)
        buffers[key] = buf
        return buf
    }

    private func makeToneBuffer(frequency: Double, duration: Double, gain: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]

        // Soft attack/release envelope to avoid clicks at the boundaries.
        let attackFrames = Int(min(0.012, duration * 0.25) * sampleRate)
        let releaseFrames = Int(min(0.060, duration * 0.55) * sampleRate)
        let total = Int(frameCount)
        let twoPiF = 2.0 * .pi * frequency / sampleRate

        for i in 0..<total {
            let env: Double
            if i < attackFrames {
                env = Double(i) / Double(max(1, attackFrames))
            } else if i > total - releaseFrames {
                env = Double(total - i) / Double(max(1, releaseFrames))
            } else {
                env = 1.0
            }
            let s = sin(twoPiF * Double(i))
            channel[i] = Float(s * env * gain)
        }
        return buffer
    }
}
