import AVFoundation
import Foundation

// Continuous, phase-continuous sine generator. Frequency can be changed in real
// time (during a finger drag) without producing clicks because we accumulate
// phase across renders. Gain has a short attack/release ramp so start/stop
// don't pop on a non-zero waveform sample.
//
// All audio-thread state lives in `RenderState` (a reference type the render
// block holds without any actor isolation). The main-actor wrapper just pokes
// atomics on it.
@MainActor
final class ToneGenerator {
    static let shared = ToneGenerator()

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let state = RenderState()
    private var sourceNode: AVAudioSourceNode?
    private(set) var isRunning = false

    private init() {
        configureSession()
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)

        let format = AVAudioFormat(standardFormatWithSampleRate: state.sampleRate, channels: 1)!
        let s = state
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            s.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: mixer, format: format)
    }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    func setFrequency(_ hz: Double) {
        state.frequency.set(max(20, min(20_000, hz)))
    }

    func play(frequency hz: Double, gain: Float = 0.32) {
        setFrequency(hz)
        state.targetGain.set(gain)
        startEngineIfNeeded()
    }

    func stop() {
        state.targetGain.set(0)
    }

    private func startEngineIfNeeded() {
        guard !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }
}

final class RenderState: @unchecked Sendable {
    let sampleRate: Double = 44_100
    let frequency = Atomic<Double>(440)
    let targetGain = Atomic<Float>(0)
    private var currentGain: Float = 0
    private var phase: Double = 0

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let freq = frequency.get()
        let target = targetGain.get()
        let increment = freq / sampleRate
        let smoothing: Float = 1.0 / Float(sampleRate * 0.008) // 8ms attack/release

        for buffer in buffers {
            guard let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            for i in 0..<min(frameCount, frames) {
                let s = Float(sin(2.0 * .pi * phase))
                if currentGain < target {
                    currentGain = min(target, currentGain + smoothing)
                } else if currentGain > target {
                    currentGain = max(target, currentGain - smoothing)
                }
                ptr[i] = s * currentGain
                phase += increment
                if phase >= 1.0 { phase -= 1.0 }
            }
        }
        return noErr
    }
}

final class Atomic<Value>: @unchecked Sendable {
    private var value: Value
    private var lock = os_unfair_lock_s()
    init(_ initial: Value) { self.value = initial }
    func get() -> Value {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return value
    }
    func set(_ new: Value) {
        os_unfair_lock_lock(&lock)
        value = new
        os_unfair_lock_unlock(&lock)
    }
}
