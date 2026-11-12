//
//  FrameMeter.swift
//  Tiny Putt
//
//  A small debug read-out of how smoothly the game runs.
//

#if DEBUG
import SwiftUI

/// Counts canvas draws and game-clock ticks. Not observed: the canvas writes to it on every
/// frame, and only a timer reads it.
final class FrameMeter {
    private var draws = 0
    private var ticks = 0
    private var lastTick = Date.timeIntervalSinceReferenceDate
    private var longestGap = 0.0

    func drew() { draws += 1 }

    func ticked() {
        let now = Date.timeIntervalSinceReferenceDate
        longestGap = max(longestGap, now - lastTick)
        lastTick = now
        ticks += 1
    }

    /// Takes the counts since the last call, over `seconds`.
    func take(over seconds: Double) -> String {
        defer { draws = 0; ticks = 0; longestGap = 0 }
        return "draw \(Int((Double(draws) / seconds).rounded())) fps · tick \(Int((Double(ticks) / seconds).rounded()))/s · worst gap \(Int((longestGap * 1000).rounded())) ms"
    }
}

struct FrameCounter: View {
    let meter: FrameMeter
    let game: GolfGame
    @State private var text = "…"

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.55)))
            .allowsHitTesting(false)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    text = meter.take(over: 0.5) + (game.isBusy ? "" : " · resting")
                }
            }
    }
}
#endif
