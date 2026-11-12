//
//  HomeView.swift
//  Tiny Putt
//

import SwiftUI

struct HomeView: View {
    let game: GolfGame
    let onPlay: () -> Void
    let onVersus: ([UUID]) -> Void

    @State private var showingSettings = false
    @State private var showingPlayers = false
    @State private var showingVersus = false

    private let theme = ThemeID.meadow

    var body: some View {
        ZStack {
            MenuScenery(theme: theme)
                .ignoresSafeArea()

            GeometryReader { geo in
                let isWide = geo.size.width > geo.size.height * 1.1
                let layout = isWide ? AnyLayout(HStackLayout(spacing: 56)) : AnyLayout(VStackLayout(spacing: 32))
                // Centred when it fits; scrolls on short screens.
                ScrollView {
                    layout {
                        hero
                        menu
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height - 32)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(game: game) }
        .sheet(isPresented: $showingPlayers) { PlayersView(game: game) }
        .sheet(isPresented: $showingVersus) { VersusSetupView(game: game) { order in
            showingVersus = false
            onVersus(order)
        } }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            BallDot(color: game.roster.current.ball, size: 46)
            Text("Tiny Putt")
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 4)
            Text("\(game.roster.current.name) · Hole \(game.roster.current.level)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var menu: some View {
        VStack(spacing: 14) {
            Button("Play", action: onPlay).buttonStyle(PillButtonStyle(prominent: true))
            Button("Versus") { showingVersus = true }
                .buttonStyle(PillButtonStyle())
                .disabled(game.roster.players.count < 2)
                .opacity(game.roster.players.count < 2 ? 0.5 : 1)
            Button("Players") { showingPlayers = true }.buttonStyle(PillButtonStyle())
            Button("Settings") { showingSettings = true }.buttonStyle(PillButtonStyle())
            if game.roster.players.count < 2 {
                Text("Add a second player to unlock Versus")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// The rough and its decoration, as a backdrop for the menus.
struct MenuScenery: View {
    let theme: ThemeID

    var body: some View {
        Canvas { ctx, size in
            let pal = theme.palette
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(pal.rough))
            let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            for item in Scenery.make(in: rect, avoiding: [], theme: theme) {
                ctx.drawScenery(item, palette: pal, theme: theme)
            }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.18)))
        }
    }
}
