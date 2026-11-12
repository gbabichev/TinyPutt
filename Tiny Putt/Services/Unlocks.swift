//
//  Unlocks.swift
//  Tiny Putt
//
//  Ball colours that are earned. A few are free from the start; the rest unlock when a player
//  reaches a goal (holes finished, holes in one, holes under par, Versus holes played and won).
//

import Foundation

/// What a player has done so far. Each player keeps their own, and unlocks are theirs alone.
struct PlayerStats: Codable, Hashable, Sendable {
    /// Holes that were holed out (a skipped hole does not count).
    var holesFinished = 0
    var holeInOnes = 0
    /// Holes holed in fewer strokes than par.
    var holesUnderPar = 0
    /// Versus holes this player took part in, and won outright (a tie wins nothing).
    var versusHoles = 0
    var versusWins = 0

    init() {}

    // Missing entries (from an older save) just start at zero.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        holesFinished = try c.decodeIfPresent(Int.self, forKey: .holesFinished) ?? 0
        holeInOnes = try c.decodeIfPresent(Int.self, forKey: .holeInOnes) ?? 0
        holesUnderPar = try c.decodeIfPresent(Int.self, forKey: .holesUnderPar) ?? 0
        versusHoles = try c.decodeIfPresent(Int.self, forKey: .versusHoles) ?? 0
        versusWins = try c.decodeIfPresent(Int.self, forKey: .versusWins) ?? 0
    }

    func value(of stat: UnlockStat) -> Int {
        switch stat {
        case .holesFinished: holesFinished
        case .holeInOnes: holeInOnes
        case .holesUnderPar: holesUnderPar
        case .versusHoles: versusHoles
        case .versusWins: versusWins
        }
    }
}

enum UnlockStat: Sendable {
    case holesFinished, holeInOnes, holesUnderPar, versusHoles, versusWins
}

/// What it takes to earn a ball colour.
struct BallUnlock: Sendable {
    let stat: UnlockStat
    let target: Int

    /// "Finish 10 holes", "Make a hole in one" ...
    var requirement: String {
        switch stat {
        case .holesFinished: "Finish \(target) holes"
        case .holeInOnes: target == 1 ? "Make a hole in one" : "Make \(target) holes in one"
        case .holesUnderPar: target == 1 ? "Finish a hole under par" : "Finish \(target) holes under par"
        case .versusHoles: "Play \(target) Versus holes"
        case .versusWins: "Win \(target) Versus holes"
        }
    }
}

extension BallColor {
    /// "Pink", "Gold" ...
    var displayName: String { rawValue.capitalized }

    /// The colours everyone starts with.
    static let free: [BallColor] = [.white, .red, .blue, .yellow]

    /// Nil for a free colour.
    var unlock: BallUnlock? {
        switch self {
        case .white, .red, .blue, .yellow: nil
        case .pink: BallUnlock(stat: .holesFinished, target: 10)
        case .purple: BallUnlock(stat: .holeInOnes, target: 1)
        case .teal: BallUnlock(stat: .holesUnderPar, target: 5)
        case .orange: BallUnlock(stat: .holesFinished, target: 30)
        case .lime: BallUnlock(stat: .versusHoles, target: 10)
        case .cyan: BallUnlock(stat: .holeInOnes, target: 5)
        case .black: BallUnlock(stat: .holesUnderPar, target: 25)
        case .gold: BallUnlock(stat: .versusWins, target: 10)
        }
    }
}

/// A ball colour a player has just earned, for the "unlocked" banner.
struct NewBall: Identifiable, Equatable {
    let id = UUID()
    let player: String
    let color: BallColor
}
