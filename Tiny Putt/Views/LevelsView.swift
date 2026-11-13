//
//  LevelsView.swift
//  Tiny Putt
//
//  Every level as a small picture of its hole, in a grid that scrolls. Any level can be played
//  again, or played ahead of the player's place in the campaign.
//

import SwiftUI

/// Holes made for the list, kept so scrolling back does not build them again.
@MainActor
final class HoleCache {
    static let shared = HoleCache()
    private final class Box { let hole: Hole; init(_ hole: Hole) { self.hole = hole } }
    private let cache = NSCache<NSNumber, Box>()

    func hole(_ level: Int) -> Hole {
        if let box = cache.object(forKey: level as NSNumber) { return box.hole }
        let hole = HoleLibrary.hole(forLevel: level)
        cache.setObject(Box(hole), forKey: level as NSNumber)
        return hole
    }
}

struct LevelsView: View {
    let game: GolfGame
    let onBack: () -> Void
    let onPlay: (Int) -> Void
    @Environment(\.screenInsets) private var insets

    private let total = HoleLibrary.count
    private let groupSize = 50
    private var side: CGFloat { max(insets.leading, insets.trailing) }

    var body: some View {
        let player = game.roster.current
        ZStack {
            MenuScenery(theme: .meadow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header(for: player)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 190), spacing: 12)], spacing: 12, pinnedViews: .sectionHeaders) {
                            ForEach(0..<((total + groupSize - 1) / groupSize), id: \.self) { group in
                                let first = group * groupSize + 1
                                let last = min(total, first + groupSize - 1)
                                Section {
                                    ForEach(first...last, id: \.self) { n in
                                        Button { onPlay(n) } label: {
                                            LevelCell(level: n, best: player.best[n], isCurrent: n == player.level, isSkipped: n < player.level && player.best[n] == nil)
                                        }
                                        .buttonStyle(.plain)
                                        .id(n)
                                    }
                                } header: {
                                    groupHeader(first: first, last: last)
                                }
                            }
                        }
                        .padding(.horizontal, 16 + side)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear { proxy.scrollTo(min(player.level, total), anchor: .center) }
                }
            }
        }
    }

    private func header(for player: Player) -> some View {
        let played = player.best.keys.filter { $0 <= total }.count
        return HStack(spacing: 12) {
            Button(action: onBack) { Image(systemName: "chevron.left") }
                .buttonStyle(RoundButtonStyle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Levels")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 2)
                Text("\(player.name) · \(played) of \(total) holes played")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
        }
        .padding(.horizontal, 16 + side)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func groupHeader(first: Int, last: Int) -> some View {
        HStack {
            Text("Holes \(first)–\(last)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Ink.dark)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Ink.cream))
                .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1.5))
            Spacer()
        }
        .padding(.top, 6)
    }
}

/// One level: a picture of the hole, its number, and the player's best score on it.
private struct LevelCell: View {
    let level: Int
    let best: Int?
    let isCurrent: Bool
    let isSkipped: Bool

    var body: some View {
        let hole = HoleCache.shared.hole(level)
        ZStack {
            Canvas { ctx, size in
                var c = ctx
                HoleRenderer.drawThumbnail(&c, size: size, hole: hole)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isCurrent ? Ink.green : .black.opacity(0.18), lineWidth: isCurrent ? 4 : 1.5))
            .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 3)
            .overlay(alignment: .topLeading) {
                Text("\(level)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Ink.cream))
                    .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1))
                    .padding(7)
            }
            .overlay(alignment: .bottomTrailing) { badge(par: hole.par) }
            .overlay(alignment: .bottomLeading) {
                if isCurrent {
                    Text("NEXT")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Ink.green))
                        .padding(7)
                }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func badge(par: Int) -> some View {
        if let best {
            let tint = best < par ? Color(hex: 0xFFE9A6) : best == par ? Color(hex: 0xBFE8C6) : Ink.cream
            HStack(spacing: 3) {
                Image(systemName: best < par ? "star.fill" : "checkmark")
                    .font(.system(size: 10, weight: .black))
                Text("\(best)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Ink.dark)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint))
            .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1))
            .padding(7)
        } else if isSkipped {
            Text("skipped")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Ink.dark.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Ink.cream.opacity(0.85)))
                .padding(7)
        }
    }
}
