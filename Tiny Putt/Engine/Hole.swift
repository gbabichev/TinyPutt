//
//  Hole.swift
//  Tiny Putt
//
//  The data that describes one hole. A hole is pure data: the physics, the renderer and the
//  (future) hole checker all read the same thing.
//

import Foundation

/// The worlds. Mostly a change of colours and scenery.
nonisolated enum ThemeID: Int, CaseIterable, Sendable {
    case meadow, farm, desert, winter
}

nonisolated enum SurfaceKind: Hashable, Sendable {
    case sand, ice, mud
    case water, lava
    /// A hill: pushes a rolling ball in this direction (units per second squared).
    case slope(Vec)
    /// A gust: pushes the ball in this direction while it is inside.
    case wind(Vec)
}

nonisolated struct Patch: Sendable {
    let kind: SurfaceKind
    let outline: [Vec]
    let lo: Vec
    let hi: Vec

    init(_ kind: SurfaceKind, _ outline: [Vec]) {
        self.kind = kind
        self.outline = outline
        let b = Poly.bounds(outline)
        lo = b.lo
        hi = b.hi
    }

    func contains(_ p: Vec) -> Bool {
        p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y && Poly.contains(outline, p)
    }
}

/// A round pinball bumper: the ball leaves it faster than it arrived.
nonisolated struct Bumper: Sendable {
    var center: Vec
    var radius: Double = 22
}

nonisolated struct Windmill: Sendable {
    var center: Vec
    var length: Double = 95
    var blades = 4
    /// Radians per second.
    var speed: Double = 1.1
    var phase: Double = 0
    var hub: Double = 16
    var thickness: Double = 10

    func angle(of blade: Int, at time: Double) -> Double {
        phase + speed * time + Double(blade) * 2 * .pi / Double(blades)
    }

    func tip(of blade: Int, at time: Double) -> Vec {
        let a = angle(of: blade, at: time)
        return center + Vec(cos(a), sin(a)) * length
    }
}

/// Pulls the ball toward it (or pushes it away, when the strength is negative).
nonisolated struct Magnet: Sendable {
    var center: Vec
    var radius: Double = 120
    var strength: Double = 700
}

nonisolated struct Segment: Sendable {
    var a: Vec
    var b: Vec
}

nonisolated struct Hole: Sendable {
    var name: String
    var theme: ThemeID
    /// The size of the world the hole is drawn in. Always fully visible on screen.
    var size: Vec
    /// The playable area. The edge is a wall.
    var outline: [Vec]
    /// Solid obstacles inside the playable area.
    var blocks: [[Vec]]
    var patches: [Patch]
    var bumpers: [Bumper]
    var windmills: [Windmill]
    var magnets: [Magnet]
    var tee: Vec
    var cup: Vec
    var par: Int
    /// Every wall as line segments, built once.
    let segments: [Segment]

    init(
        name: String,
        theme: ThemeID = .meadow,
        size: Vec = Vec(600, 900),
        outline: [Vec],
        blocks: [[Vec]] = [],
        patches: [Patch] = [],
        bumpers: [Bumper] = [],
        windmills: [Windmill] = [],
        magnets: [Magnet] = [],
        tee: Vec,
        cup: Vec,
        par: Int
    ) {
        self.name = name
        self.theme = theme
        self.size = size
        self.outline = outline
        self.blocks = blocks
        self.patches = patches
        self.bumpers = bumpers
        self.windmills = windmills
        self.magnets = magnets
        self.tee = tee
        self.cup = cup
        self.par = par
        var segs: [Segment] = []
        for loop in [outline] + blocks {
            for i in 0..<loop.count { segs.append(Segment(a: loop[i], b: loop[(i + 1) % loop.count])) }
        }
        segments = segs
    }
}
