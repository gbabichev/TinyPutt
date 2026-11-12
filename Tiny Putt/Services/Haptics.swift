//
//  Haptics.swift
//  Tiny Putt
//

import Foundation
#if os(iOS)
import UIKit
#endif

/// Small taps for hitting the ball, bouncing and sinking a putt. Only iPhone has the hardware,
/// and the Mac does nothing on purpose: no buzzing a trackpad.
final class Haptics {
    var isEnabled = true {
        didSet { if !isEnabled { endAim() } }
    }

    #if os(iOS)
    private let wall = UIImpactFeedbackGenerator(style: .rigid)
    private let buzz = UIImpactFeedbackGenerator(style: .medium)
    private var aimTask: Task<Void, Never>?
    private var aimPower = 0.0
    #endif

    /// Whether this device can do haptics at all (so Settings can hide the switch).
    static var isAvailable: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    func hit(power: Double) {
        #if os(iOS)
        guard isEnabled else { return }
        let style: UIImpactFeedbackGenerator.FeedbackStyle = power > 0.66 ? .heavy : power > 0.33 ? .medium : .light
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    /// One tap for every wall hit, harder for a harder hit (never so soft it cannot be felt).
    func bounce(strength: Double) {
        #if os(iOS)
        guard isEnabled else { return }
        wall.impactOccurred(intensity: max(0.35, min(1, strength)))
        wall.prepare()
        #endif
    }

    // MARK: - Drag

    /// Begins the buzz that builds while the ball is being pulled back: a quick run of taps that
    /// is silent at first and gets stronger and faster as the pull gets longer (`updateAim`).
    func startAim() {
        #if os(iOS)
        guard isEnabled, aimTask == nil else { return }
        aimPower = 0
        buzz.prepare()
        aimTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let p = self.aimPower
                if p > 0.03 {
                    self.buzz.impactOccurred(intensity: CGFloat(0.1 + 0.9 * p * p))
                    self.buzz.prepare()
                }
                // From a tap every 90 ms at the start to one every 35 ms at full pull.
                let gap = 0.09 - 0.055 * p
                try? await Task.sleep(for: .seconds(gap))
            }
        }
        #endif
    }

    /// `power` runs from 0 to 1. Nothing is felt near 0; the buzz is strongest at 1.
    func updateAim(power: Double) {
        #if os(iOS)
        aimPower = max(0, min(1, power))
        #endif
    }

    func endAim() {
        #if os(iOS)
        aimTask?.cancel()
        aimTask = nil
        aimPower = 0
        #endif
    }

    func bumper() {
        #if os(iOS)
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
        #endif
    }

    func hazard() {
        #if os(iOS)
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    func success() {
        #if os(iOS)
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
