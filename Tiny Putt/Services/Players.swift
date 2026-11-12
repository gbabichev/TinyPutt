//
//  Players.swift
//  Tiny Putt
//

import Foundation
import Observation
import SwiftUI

enum BallColor: String, CaseIterable, Codable, Sendable {
    case white, red, blue, yellow, pink, orange, purple, teal

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
        }
    }
}

/// One person who plays. Each player has their own place in the levels and their own best scores.
struct Player: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var ball: BallColor
    /// The level this player is on.
    var level = 1
    /// The fewest strokes taken on each level.
    var best: [Int: Int] = [:]
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
        let ball = BallColor.allCases.first { !used.contains($0) } ?? .white
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
        guard let i = players.firstIndex(where: { $0.id == id }) else { return }
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
