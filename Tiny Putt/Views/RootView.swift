//
//  RootView.swift
//  Tiny Putt
//

import SwiftUI

struct RootView: View {
    enum Screen { case home, levels, game }

    @State private var game = GolfGame()
    @State private var screen = Screen.home

    var body: some View {
        FullWidth {
            screens
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        // Let the picture show right up to the top of the window, instead of a solid title bar.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
    }

    private var screens: some View {
        ZStack {
            switch screen {
            case .home:
                HomeView(game: game, onPlay: {
                    game.startCampaign()
                    screen = .game
                }, onLevels: {
                    screen = .levels
                }, onVersus: { order in
                    game.startVersus(order: order)
                    screen = .game
                })
                .transition(.opacity)
            case .levels:
                LevelsView(game: game, onBack: { screen = .home }, onPlay: { n in
                    game.startLevel(n)
                    screen = .game
                })
                .transition(.opacity)
            case .game:
                GameView(game: game) {
                    // A level picked from the list goes back to the list; everything else to the menu.
                    let backToLevels = game.isPicked
                    screen = backToLevels ? .levels : .home
                    // Reset the game only once the course has faded out, so the next hole is
                    // never seen on the way out.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        if screen != .game { game.leave() }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
