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
                    game.leave()
                    screen = .home
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
