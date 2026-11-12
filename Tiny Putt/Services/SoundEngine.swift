//
//  SoundEngine.swift
//  Tiny Putt
//

import AVFoundation

/// Tiny synthesized sound effects, made in code so the app ships no audio files.
/// Started from TerrainGolf's engine, with a bumper ping and a lava sizzle added.
final class SoundEngine {
    enum Effect {
        /// `power` runs from 0 to 1.
        case hit(power: Double)
        /// `impact` runs from 0 to 1.
        case bounce(impact: Double)
        case bumper
        case cup
        case splash
        case lava
    }

    var isEnabled = true

    private static let sampleRate = 44_100.0

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var isReady = false
    private var idlePause: Task<Void, Never>?

    private var hitBuffers: [AVAudioPCMBuffer] = []
    private var bounceBuffers: [AVAudioPCMBuffer] = []
    private var bumperBuffer: AVAudioPCMBuffer?
    private var cupBuffer: AVAudioPCMBuffer?
    private var splashBuffer: AVAudioPCMBuffer?
    private var lavaBuffer: AVAudioPCMBuffer?

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        hitBuffers = [0.15, 0.5, 0.9].map(makeHit)
        bounceBuffers = [(330.0, 0.15), (440.0, 0.5), (550.0, 0.9)].map { makeBounce(frequency: $0.0, impact: $0.1) }
        bumperBuffer = makeBumper()
        cupBuffer = makeCup()
        splashBuffer = makeSplash()
        lavaBuffer = makeLava()
        do {
            try engine.start()
            isReady = true
            // Nothing to play yet: let the engine rest until the first sound.
            engine.pause()
        } catch {
            isReady = false
        }
    }

    /// Wakes a resting engine ahead of the first sound (restarting audio hardware can take a
    /// few hundred milliseconds, so it is done when a drag begins rather than at the hit).
    func prepare() {
        guard isReady, isEnabled else { return }
        if engine.isRunning {
            scheduleIdlePause()
        } else {
            let engine = engine
            DispatchQueue.global(qos: .userInitiated).async {
                try? engine.start()
            }
            scheduleIdlePause()
        }
    }

    func play(_ effect: Effect) {
        guard isReady, isEnabled else { return }
        let buffer: AVAudioPCMBuffer?
        switch effect {
        case .hit(let power): buffer = hitBuffers[min(2, Int(power * 3))]
        case .bounce(let impact): buffer = bounceBuffers[min(2, Int(impact * 3))]
        case .bumper: buffer = bumperBuffer
        case .cup: buffer = cupBuffer
        case .splash: buffer = splashBuffer
        case .lava: buffer = lavaBuffer
        }
        guard let buffer else { return }
        wakeEngine()
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func wakeEngine() {
        if !engine.isRunning { try? engine.start() }
        scheduleIdlePause()
    }

    private func scheduleIdlePause() {
        idlePause?.cancel()
        idlePause = Task { [weak self] in
            // Longer than any shot, so the engine is never paused mid-flight.
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self else { return }
            for player in players { player.stop() }
            engine.pause()
        }
    }

    // MARK: - Synthesis

    private func render(duration: Double, _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * Self.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = unsafe buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            unsafe channel[i] = Float(sample(Double(i) / Self.sampleRate))
        }
        return buffer
    }

    /// A metal putter face striking a golf ball: a sharp click, a short inharmonic metallic ring
    /// (a struck bar does not ring at a clean pitch, which is what makes it sound like metal and
    /// not like a synth tone) and a low thump from the ball. A harder hit is louder and brighter.
    private func makeHit(power: Double) -> AVAudioPCMBuffer {
        let base = 1700 + 900 * power                       // pitch of the metal ring
        let ratios: [Double] = [1.0, 2.76, 5.40, 8.93]      // the modes of a struck metal bar
        let gains: [Double] = [1.0, 0.65, 0.4, 0.22]
        let decays: [Double] = [70, 95, 140, 200]           // per second: higher modes die first
        let level = 0.5 + 0.5 * power
        var lowpass = 0.0
        return render(duration: 0.28) { t in
            // The click: a few milliseconds of noise with the low end taken out.
            let raw = Double.random(in: -1...1)
            lowpass += (raw - lowpass) * 0.25
            let click = (raw - lowpass) * exp(-t * 700) * (0.9 + 0.5 * power)

            var ring = 0.0
            for k in 0..<ratios.count {
                ring += sin(2 * Double.pi * base * ratios[k] * t) * gains[k] * exp(-t * decays[k])
            }
            ring *= 0.22 * (0.6 + 0.6 * power)

            // The ball: a short dull knock, with no pitch sweep.
            let thump = sin(2 * Double.pi * (150 - 20 * min(1, t * 20)) * t) * exp(-t * 55) * 0.55

            return (click + ring + thump) * level * 0.85
        }
    }

    /// The ball against a wall: the same family as the putt, but lighter. The old pitched knock
    /// stays underneath, with a small click on the front and a short, quiet metallic tick.
    private func makeBounce(frequency: Double, impact: Double) -> AVAudioPCMBuffer {
        let base = 1300 + 600 * impact
        let ratios: [Double] = [1.0, 2.76, 5.40]
        let gains: [Double] = [1.0, 0.55, 0.3]
        let decays: [Double] = [150, 210, 300]
        var lowpass = 0.0
        return render(duration: 0.12) { t in
            let body = sin(2 * Double.pi * frequency * t) * exp(-t * 35) * 0.3

            let raw = Double.random(in: -1...1)
            lowpass += (raw - lowpass) * 0.25
            let click = (raw - lowpass) * exp(-t * 900) * (0.3 + 0.3 * impact)

            var tick = 0.0
            for k in 0..<ratios.count {
                tick += sin(2 * Double.pi * base * ratios[k] * t) * gains[k] * exp(-t * decays[k])
            }
            tick *= 0.07 * (0.6 + 0.6 * impact)

            return body + click + tick
        }
    }

    /// A bright pinball "boing".
    private func makeBumper() -> AVAudioPCMBuffer {
        render(duration: 0.22) { t in
            let f = 620 + 520 * exp(-t * 18)
            let tone = sin(2 * Double.pi * f * t) + 0.35 * sin(4 * Double.pi * f * t)
            return tone * exp(-t * 16) * 0.3
        }
    }

    /// A soft, bubbly splash: smoothed noise that fades away.
    private func makeSplash() -> AVAudioPCMBuffer {
        var smooth = 0.0
        return render(duration: 0.45) { t in
            smooth += (Double.random(in: -1...1) - smooth) * 0.18
            let bubble = sin(2 * Double.pi * (300 + 700 * t) * t) * exp(-t * 10) * 0.25
            return (smooth * exp(-t * 7) * 1.4 + bubble) * 0.5
        }
    }

    /// A hiss and a low pop.
    private func makeLava() -> AVAudioPCMBuffer {
        var smooth = 0.0
        return render(duration: 0.6) { t in
            smooth += (Double.random(in: -1...1) - smooth) * 0.5
            let hiss = smooth * exp(-t * 5) * 0.5
            let pop = sin(2 * Double.pi * (160 - 90 * t) * t) * exp(-t * 14) * 0.5
            return hiss + pop
        }
    }

    /// A bright little bell arpeggio for sinking the putt.
    private func makeCup() -> AVAudioPCMBuffer {
        let notes: [Double] = [523.25, 659.25, 783.99, 1046.5]
        return render(duration: 1.1) { t in
            var value = 0.0
            for (i, f) in notes.enumerated() {
                let local = t - Double(i) * 0.09
                guard local > 0 else { continue }
                let env = exp(-local * 6)
                value += (sin(2 * Double.pi * f * local) + 0.3 * sin(4 * Double.pi * f * local)) * env
            }
            return value * 0.22
        }
    }
}
