//
//  GameView.swift
//  Tiny Putt
//

import SwiftUI

struct GameView: View {
    let game: GolfGame
    let onExit: () -> Void
    @Environment(\.screenInsets) private var insets
    /// The corner buttons sit the same distance from both side edges: the wider gutter wins.
    private var side: CGFloat { max(insets.leading, insets.trailing) }
    /// A tall gutter along the top (the Duo in portrait) holds the clock and Wi-Fi. The HUD moves
    /// up into it as one compact row, so it neither sits far below nor lands on those icons.
    private var inStatusStrip: Bool { insets.top > 70 }
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

            // The scoreboard is centred on the whole display; the corner buttons keep clear of the
            // side gutters (the camera strip), by the insets passed down from the root.
            hud
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container, edges: inStatusStrip ? .top : [])

            #if DEBUG
            if showFPS {
                FrameCounter(meter: meter, game: game)
                    .padding(.horizontal, 12)
                    .padding(.leading, side)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            debugMenu
                .padding(.horizontal, 12)
                .padding(.trailing, side)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            #endif

            if game.overlay != .none {
                Color.black.opacity(0.25).ignoresSafeArea()
                ResultCard(game: game, onExit: onExit)
                    .transition(.scale(scale: 0.92))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { game.topReserve = $0 > 70 ? 84 : $0 + 70 }
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

    private var scoreboard: some View {
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
    }

    private var exitButton: some View {
        Button(action: onExit) { Image(systemName: "xmark") }
    }

    private var restartButton: some View {
        Button { game.replayHole() } label: { Image(systemName: "arrow.counterclockwise") }
    }

    @ViewBuilder private var hud: some View {
        if inStatusStrip {
            HStack(spacing: 10) {
                exitButton
                scoreboard
                restartButton
            }
            .buttonStyle(RoundButtonStyle())
            .padding(.top, 14)
        } else {
            ZStack(alignment: .top) {
                scoreboard
                HStack {
                    exitButton
                    Spacer()
                    restartButton
                }
                .padding(.horizontal, side)
                .buttonStyle(RoundButtonStyle())
            }
        }
    }
}

/// The "Next hole" button on the result card. It fills up as a countdown and moves on by itself
/// when it is full, so a round flows into the next hole without a tap. Tapping it skips the wait;
/// leaving the screen (Menu, Finish, Play again) cancels it.
private struct NextHoleButton: View {
    let game: GolfGame
    /// Seconds before it continues on its own.
    static let delay = 3.0
    @State private var progress = 0.0

    var body: some View {
        Button("Next hole") { game.next() }
            .buttonStyle(PillButtonStyle(prominent: true))
            .overlay {
                // One continuous animation (not a state update every few milliseconds), so it
                // runs at the display's own frame rate.
                // A plain bar growing from the left, clipped to the button's own capsule, so
                // it can never poke out past the edge.
                Rectangle()
                    .fill(.white.opacity(0.28))
                    .scaleEffect(x: progress, anchor: .leading)
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
            }
            .task {
                withAnimation(.linear(duration: Self.delay)) { progress = 1 }
                try? await Task.sleep(for: .seconds(Self.delay))
                if !Task.isCancelled { game.next() }
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
                NextHoleButton(game: game)
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
                    NextHoleButton(game: game)
                    Button("Finish", action: onExit).buttonStyle(PillButtonStyle())
                }

            case .skipOffer:
                Text("Tough hole?")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                Text(game.versus == nil
                     ? "\(game.strokes) strokes so far. Skip it and move on?"
                     : "\(game.strokes) strokes so far. Skip it? Your turn ends with those strokes.")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.dark.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button("Skip hole") { game.skipHole() }.buttonStyle(PillButtonStyle(prominent: true))
                Button("Keep playing") { game.keepPlaying() }.buttonStyle(PillButtonStyle())

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
