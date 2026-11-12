//
//  GameView.swift
//  Tiny Putt
//

import SwiftUI

struct GameView: View {
    let game: GolfGame
    let onExit: () -> Void
    #if DEBUG
    @State private var askingForHole = false
    @State private var holeText = ""
    @AppStorage("debugShowFPS") private var showFPS = true
    private let meter = FrameMeter()
    #endif

    var body: some View {
        ZStack {
            // The course fills the whole screen, behind the notch and the Duo's side strip.
            GeometryReader { geo in
                world
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { game.updateAim(start: $0.startLocation, current: $0.location, size: geo.size) }
                            .onEnded { _ in game.releaseAim() }
                    )
            }
            .ignoresSafeArea()

            // The buttons stay inside the safe area.
            hud
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            #if DEBUG
            if showFPS {
                FrameCounter(meter: meter)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            debugMenu
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            #endif

            if game.overlay != .none {
                Color.black.opacity(0.25).ignoresSafeArea()
                ResultCard(game: game, onExit: onExit)
                    .transition(.scale(scale: 0.92))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { game.topReserve = $0 + 70 }
        .animation(.spring(duration: 0.35), value: game.overlay)
        #if DEBUG
        .alert("Go to hole", isPresented: $askingForHole) {
            TextField("Hole number", text: $holeText)
            Button("Go") {
                if let n = Int(holeText.trimmingCharacters(in: .whitespaces)) { game.debugGoToHole(n) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Any hole from 1 up.")
        }
        #endif
    }

    private var world: some View {
        #if DEBUG
        WorldView(game: game, meter: meter)
        #else
        WorldView(game: game)
        #endif
    }

    #if DEBUG
    private var debugMenu: some View {
        Menu {
            Button("Next hole", systemImage: "forward.fill") { game.debugGoToHole(game.level + 1) }
            Button("Previous hole", systemImage: "backward.fill") { game.debugGoToHole(game.level - 1) }
                .disabled(game.level <= 1)
            Toggle("Frame rate", systemImage: "speedometer", isOn: $showFPS)
            Button("Go to hole…", systemImage: "flag.fill") {
                holeText = "\(game.level)"
                askingForHole = true
            }
        } label: {
            Image(systemName: "ladybug.fill")
        }
        .menuStyle(.button)
        .buttonStyle(RoundButtonStyle())
        .menuIndicator(.hidden)
        .accessibilityLabel("Debug menu")
    }
    #endif

    private var hud: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 2) {
                Text("HOLE \(game.level) · PAR \(game.hole.par)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                HStack(spacing: 5) {
                    BallDot(color: game.ballColor, size: 11)
                    Text("\(game.playerName) · STROKES \(game.strokes)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .opacity(0.65)
                }
            }
            .foregroundStyle(Ink.dark)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Capsule().fill(Ink.cream))
            .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 2)
            HStack {
                Button(action: onExit) { Image(systemName: "xmark") }
                Spacer()
                Button { game.replayHole() } label: { Image(systemName: "arrow.counterclockwise") }
            }
            .buttonStyle(RoundButtonStyle())
        }
    }
}

/// What shows after a hole is finished.
struct ResultCard: View {
    let game: GolfGame
    let onExit: () -> Void

    var body: some View {
        Card {
            switch game.overlay {
            case .campaignDone:
                Text(game.scoreTitle)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                Text("\(game.strokes) \(game.strokes == 1 ? "stroke" : "strokes") · par \(game.hole.par)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.dark.opacity(0.7))
                Button("Next hole") { game.next() }.buttonStyle(PillButtonStyle(prominent: true))
                Button("Play again") { game.replayHole() }.buttonStyle(PillButtonStyle())
                Button("Menu", action: onExit).buttonStyle(PillButtonStyle())

            case .versusTurnDone:
                if let v = game.versus {
                    Text("\(game.playerName) · \(game.strokes) \(game.strokes == 1 ? "stroke" : "strokes")")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.dark)
                    let upNext = game.roster.player(v.order[v.turn + 1])
                    Button("\(upNext?.name ?? "Next") is up") { game.next() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }

            case .versusHoleDone:
                if let v = game.versus {
                    Text("Hole \(game.level)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.dark)
                    let best = v.order.compactMap { v.holeStrokes[$0] }.min()
                    HStack(spacing: 0) {
                        Spacer()
                        Text("THIS HOLE").frame(width: 82, alignment: .trailing)
                        Text("TOTAL").frame(width: 62, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Ink.dark.opacity(0.55))
                    ForEach(v.order, id: \.self) { id in
                        if let p = game.roster.player(id) {
                            let strokes = v.holeStrokes[id] ?? 0
                            HStack(spacing: 0) {
                                BallDot(color: p.ball, size: 18)
                                Text(p.name).padding(.leading, 8)
                                if v.order.count > 1, strokes == best {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color(hex: 0xE0A526))
                                        .padding(.leading, 6)
                                }
                                Spacer()
                                Text("\(strokes)").frame(width: 82, alignment: .trailing)
                                Text("\(v.totals[id] ?? 0)")
                                    .opacity(0.6)
                                    .frame(width: 62, alignment: .trailing)
                            }
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Ink.dark)
                        }
                    }
                    Button("Next hole") { game.next() }.buttonStyle(PillButtonStyle(prominent: true))
                    Button("Finish", action: onExit).buttonStyle(PillButtonStyle())
                }

            case .none:
                EmptyView()
            }
        }
    }
}

/// The course, drawn on its own so a redraw does not re-evaluate the buttons above it. It also
/// runs the game clock: about 60 times a second while anything moves, and far less when the
/// game is at rest.
private struct WorldView: View {
    let game: GolfGame
    #if DEBUG
    let meter: FrameMeter
    #endif
    @State private var frame = 0

    var body: some View {
        Canvas { ctx, size in
            // Reading `frame` ties each redraw to the game clock.
            _ = frame
            #if DEBUG
            meter.drew()
            #endif
            HoleRenderer.draw(&ctx, size: size, game: game)
        }
        .task {
            while !Task.isCancelled {
                game.advance(to: .now)
                #if DEBUG
                meter.ticked()
                #endif
                frame &+= 1
                try? await Task.sleep(for: game.isBusy ? .milliseconds(16) : .milliseconds(33))
            }
        }
    }
}
