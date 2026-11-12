//
//  PlayersView.swift
//  Tiny Putt
//

import SwiftUI

/// Add, rename and remove players, and choose who plays next.
struct PlayersView: View {
    let game: GolfGame
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: "Players", onDone: { dismiss() }) {
            ForEach(game.roster.players) { player in
                PlayerRow(game: game, player: player)
            }
            if game.roster.canAddPlayer {
                Button { game.roster.add() } label: { Label("Add player", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }
}

private struct PlayerRow: View {
    let game: GolfGame
    let player: Player
    @State private var name: String

    init(game: GolfGame, player: Player) {
        self.game = game
        self.player = player
        _name = State(initialValue: player.name)
    }

    private var isCurrent: Bool { game.roster.currentID == player.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { game.roster.select(player.id) } label: {
                    Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Ink.green)
                }
                .buttonStyle(.plain)
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                    .onSubmit { game.roster.rename(player.id, to: name) }
                    .onChange(of: name) { _, new in game.roster.rename(player.id, to: new) }
                Text("Hole \(player.level)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.dark.opacity(0.6))
                if game.roster.players.count > 1 {
                    Button { game.roster.remove(player.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Ink.dark.opacity(0.55))
                }
            }
            HStack(spacing: 8) {
                ForEach(BallColor.allCases, id: \.self) { color in
                    Button { game.roster.setBall(player.id, to: color) } label: {
                        BallDot(color: color, size: 24)
                            .overlay(Circle().stroke(Ink.dark, lineWidth: player.ball == color ? 3 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.55)))
    }
}

/// Picks who plays a versus game, in the order they are tapped.
struct VersusSetupView: View {
    let game: GolfGame
    let onStart: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var order: [UUID] = []

    var body: some View {
        SheetFrame(title: "Versus", onDone: { dismiss() }) {
            Text("Tap players in the order they will play. Each one plays the hole until the ball is in, then the next one goes.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.dark.opacity(0.75))
                .multilineTextAlignment(.center)
            ForEach(game.roster.players) { player in
                Button {
                    if let i = order.firstIndex(of: player.id) { order.remove(at: i) } else { order.append(player.id) }
                } label: {
                    HStack(spacing: 12) {
                        BallDot(color: player.ball, size: 24)
                        Text(player.name)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                        Spacer()
                        if let i = order.firstIndex(of: player.id) {
                            Text("\(i + 1)")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Ink.green))
                        }
                    }
                    .foregroundStyle(Ink.dark)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(order.contains(player.id) ? 0.85 : 0.5)))
                }
                .buttonStyle(.plain)
            }
            Button("Start") { onStart(order) }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(order.count < 2)
                .opacity(order.count < 2 ? 0.5 : 1)
        }
        .onAppear { order = game.roster.players.map(\.id) }
    }
}

/// The common frame for the sheets: a title, a scrolling column and a Done button.
struct SheetFrame<Content: View>: View {
    let title: String
    let onDone: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Ink.cream.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.dark)
                    Spacer()
                    Button("Done", action: onDone)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.green)
                        .buttonStyle(.plain)
                }
                .padding(20)
                ScrollView {
                    VStack(spacing: 12) { content }
                        .frame(maxWidth: 480)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}
