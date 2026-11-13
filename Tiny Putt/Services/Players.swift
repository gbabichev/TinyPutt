//
//  Players.swift
//  Tiny Putt
//

import Foundation
import Observation
import SwiftUI

enum BallColor: String, CaseIterable, Codable, Sendable {
    case white, red, blue, yellow, pink, orange, purple, teal, lime, cyan, black, gold

    var color: Color {
        switch self {
        case .white: Color(hex: 0xFFFFFF)
        case .red: Color(hex: 0xE5484D)
        case .blue: Color(hex: 0x3E7BFA)
        case .yellow: Color(hex: 0xF5C518)
        case .pink: Color(hex: 0xF06BAA)
        case .orange: Color(hex: 0xF5822A)
        case .purple: Color(hex: 0x8B5CF6)
        case .teal: Color(hex: 0x14B8A6)
        case .lime: Color(hex: 0x84CC16)
        case .cyan: Color(hex: 0x22D3EE)
        case .black: Color(hex: 0x2B2B33)
        case .gold: Color(hex: 0xE0A526)
        }
    }
}

/// One person who plays. Each player has their own place in the levels, their own best scores
/// and their own unlocked ball colours.
struct Player: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var ball: BallColor
    /// The level this player is on.
    var level = 1
    /// The fewest strokes taken on each level.
    var best: [Int: Int] = [:]
    var stats = PlayerStats()
    /// The ball colours this player can use.
    var owned: [BallColor] = BallColor.free

    init(id: UUID, name: String, ball: BallColor) {
        self.id = id
        self.name = name
        self.ball = ball
        owned = BallColor.free.contains(ball) ? BallColor.free : BallColor.free + [ball]
    }

    // Older saves have no stats or colours: they start from zero, and keep the colour they chose.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        ball = try c.decode(BallColor.self, forKey: .ball)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
        best = try c.decodeIfPresent([Int: Int].self, forKey: .best) ?? [:]
        stats = try c.decodeIfPresent(PlayerStats.self, forKey: .stats) ?? PlayerStats()
        var colours = try c.decodeIfPresent([BallColor].self, forKey: .owned) ?? BallColor.free
        if !colours.contains(ball) { colours.append(ball) }
        owned = colours
    }

    func owns(_ color: BallColor) -> Bool { owned.contains(color) }
}

@MainActor
@Observable
final class PlayerRoster {
    static let storageKey = "players.v1"
    static let maximumPlayers = 8

    private(set) var players: [Player]
    private(set) var currentID: UUID
    @ObservationIgnored private let defaults: UserDefaults

    private struct Saved: Codable {
        var players: [Player]
        var currentID: UUID
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data), !saved.players.isEmpty {
            players = saved.players
            currentID = saved.players.contains { $0.id == saved.currentID } ? saved.currentID : saved.players[0].id
        } else {
            let first = Player(id: UUID(), name: "Player 1", ball: .white)
            players = [first]
            currentID = first.id
            save()
        }
    }

    var current: Player { player(currentID) ?? players[0] }
    var canAddPlayer: Bool { players.count < Self.maximumPlayers }

    func player(_ id: UUID) -> Player? { players.first { $0.id == id } }

    @discardableResult
    func add() -> Player {
        let used = Set(players.map(\.ball))
        let ball = BallColor.free.first { !used.contains($0) } ?? .white
        let player = Player(id: UUID(), name: "Player \(players.count + 1)", ball: ball)
        players.append(player)
        save()
        return player
    }

    func select(_ id: UUID) {
        guard player(id) != nil, id != currentID else { return }
        currentID = id
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = players.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        players[i].name = String((trimmed.isEmpty ? players[i].name : trimmed).prefix(14))
        save()
    }

    func setBall(_ id: UUID, to ball: BallColor) {
        guard let i = players.firstIndex(where: { $0.id == id }), players[i].owns(ball) else { return }
        players[i].ball = ball
        save()
    }

    /// The last player cannot be removed.
    func remove(_ id: UUID) {
        guard players.count > 1 else { return }
        players.removeAll { $0.id == id }
        if currentID == id { currentID = players[0].id }
        save()
    }

    /// Notes a finished level: the personal best, and moving on to the next level.
    func finish(level: Int, strokes: Int, for id: UUID) {
        guard let i = players.firstIndex(where: { $0.id == id }) else { return }
        players[i].best[level] = min(players[i].best[level] ?? .max, strokes)
        players[i].level = max(players[i].level, level + 1)
        save()
    }

    /// Notes a hole replayed (or played out of turn) from the level list: the personal best, and nothing else.
    func recordBest(level: Int, strokes: Int, for id: UUID) {
        guard let i = players.firstIndex(where: { $0.id == id }) else { return }
        players[i].best[level] = min(players[i].best[level] ?? .max, strokes)
        save()
    }

    /// Notes a hole that was played: counts it, and returns any ball colours it unlocked.
    /// `holed` is false for a hole that was skipped.
    @discardableResult
    func recordHole(strokes: Int, par: Int, holed: Bool, versus: Bool, for id: UUID) -> [BallColor] {
        guard let i = players.firstIndex(where: { $0.id == id }) else { return [] }
        if holed {
            players[i].stats.holesFinished += 1
            if strokes == 1 { players[i].stats.holeInOnes += 1 }
            if strokes < par { players[i].stats.holesUnderPar += 1 }
        }
        if versus { players[i].stats.versusHoles += 1 }
        return unlockEarned(at: i)
    }

    /// A Versus hole won outright.
    @discardableResult
    func recordVersusWin(for id: UUID) -> [BallColor] {
        guard let i = players.firstIndex(where: { $0.id == id }) else { return [] }
        players[i].stats.versusWins += 1
        return unlockEarned(at: i)
    }

    /// Adds any colour whose goal has now been reached, and saves.
    private func unlockEarned(at i: Int) -> [BallColor] {
        var earned: [BallColor] = []
        for color in BallColor.allCases where !players[i].owns(color) {
            if let goal = color.unlock, players[i].stats.value(of: goal.stat) >= goal.target {
                players[i].owned.append(color)
                earned.append(color)
            }
        }
        save()
        return earned
    }

    /// Moves on past a level without finishing it: no best is recorded for it.
    func skip(level: Int, for id: UUID) {
        guard let i = players.firstIndex(where: { $0.id == id }) else { return }
        players[i].level = max(players[i].level, level + 1)
        save()
    }

    func resetAll() {
        let first = Player(id: UUID(), name: "Player 1", ball: .white)
        players = [first]
        currentID = first.id
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Saved(players: players, currentID: currentID)) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
