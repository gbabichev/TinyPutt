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
    var isEnabled = true

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

    func bounce(strength: Double) {
        #if os(iOS)
        guard isEnabled, strength > 0.15 else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: min(1, strength))
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
