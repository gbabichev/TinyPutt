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

/// A dish or a hill in the ground. A dish pulls the ball toward its middle, so a shot passing by
/// bends in; a hill (negative strength) pushes it away, so a cup on top is hard to hold. The
/// push grows toward the rim and fades to nothing at the centre.
nonisolated struct Bowl: Sendable {
    var center: Vec
    var radius: Double = 115
    /// Push at the rim, in units per second squared (grass friction is 300, so a slope past that moves a resting ball). Negative is a hill.
    var strength: Double = 340

    var isHill: Bool { strength < 0 }
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
    var bowls: [Bowl]
    var tee: Vec
    var cup: Vec
    var par: Int
    /// Every wall as line segments, built once.
    let segments: [Segment]
    // A grid over the walls, so the physics only tests the few segments near the ball.
    let gridOrigin: Vec
    let gridCols: Int
    let gridRows: Int
    let cellStart: [Int32]
    let cellSegments: [Int32]
    static let cellSize = 32.0

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
        bowls: [Bowl] = [],
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
        self.bowls = bowls
        self.tee = tee
        self.cup = cup
        self.par = par
        var segs: [Segment] = []
        for loop in [outline] + blocks {
            for i in 0..<loop.count { segs.append(Segment(a: loop[i], b: loop[(i + 1) % loop.count])) }
        }
        segments = segs

        // Build the wall grid (each segment is listed in every cell it could touch).
        var lo = Vec(.infinity, .infinity), hi = Vec(-.infinity, -.infinity)
        for sg in segs {
            lo.x = min(lo.x, sg.a.x, sg.b.x); lo.y = min(lo.y, sg.a.y, sg.b.y)
            hi.x = max(hi.x, sg.a.x, sg.b.x); hi.y = max(hi.y, sg.a.y, sg.b.y)
        }
        let origin = Vec(lo.x - 40, lo.y - 40)
        let cols = Int((hi.x - lo.x + 80) / Self.cellSize) + 1
        let rows = Int((hi.y - lo.y + 80) / Self.cellSize) + 1
        var buckets = [[Int32]](repeating: [], count: cols * rows)
        let reach = 12.0   // ball radius plus a step of travel
        for (i, sg) in segs.enumerated() {
            let x0 = Int((min(sg.a.x, sg.b.x) - reach - origin.x) / Self.cellSize)
            let x1 = Int((max(sg.a.x, sg.b.x) + reach - origin.x) / Self.cellSize)
            let y0 = Int((min(sg.a.y, sg.b.y) - reach - origin.y) / Self.cellSize)
            let y1 = Int((max(sg.a.y, sg.b.y) + reach - origin.y) / Self.cellSize)
            for cy in max(0, y0)...min(rows - 1, y1) {
                for cx in max(0, x0)...min(cols - 1, x1) { buckets[cy * cols + cx].append(Int32(i)) }
            }
        }
        var starts = [Int32](repeating: 0, count: cols * rows + 1)
        var flat: [Int32] = []
        for (i, b) in buckets.enumerated() {
            starts[i] = Int32(flat.count)
            flat.append(contentsOf: b)
        }
        starts[cols * rows] = Int32(flat.count)
        gridOrigin = origin
        gridCols = cols
        gridRows = rows
        cellStart = starts
        cellSegments = flat
    }
}
