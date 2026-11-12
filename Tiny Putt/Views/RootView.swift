//
//  RootView.swift
//  Tiny Putt
//

import SwiftUI

struct RootView: View {
    enum Screen { case home, game }

    @State private var game = GolfGame()
    @State private var screen = Screen.home

    var body: some View {
        ZStack {
            switch screen {
            case .home:
                HomeView(game: game, onPlay: {
                    game.startCampaign()
                    screen = .game
                }, onVersus: { order in
                    game.startVersus(order: order)
                    screen = .game
                })
                .transition(.opacity)
            case .game:
                GameView(game: game) {
                    screen = .home
                    // Reset the game only once the course has faded out, so the next hole is
                    // never seen on the way to the menu.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        if screen == .home { game.leave() }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }
}
