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
    /// A speed pad: a ball rolling onto it is kicked along this direction.
    case boost(Vec)
    /// A plank bridge over water or lava: the ball is safe on it.
    case bridge
    /// A ramp: a ball going up it takes off and flies over whatever is below (heading this way).
    case ramp(Vec)
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

nonisolated enum WindmillStyle: Sendable { case windmill, spinner }

nonisolated struct Windmill: Sendable {
    var style: WindmillStyle = .windmill
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

/// Two openings joined together: a ball that rolls into one comes out of the other, still moving.
/// A tunnel is the same with a covered pipe between them, so the ball is out of sight for a moment.
nonisolated struct Portal: Sendable {
    var a: Vec
    var b: Vec
    var radius: Double = 15
    /// Seconds the ball spends inside (0 for a portal).
    var delay: Double = 0
    var isTunnel: Bool { delay > 0 }
}

/// A wall that moves with time: it slides, or swings about a pivot. Described by the wall at rest
/// (a line from `p0` to `p1`) and how far it moves; a ball is knocked by it like by a windmill blade.
nonisolated struct Mover: Sendable {
    enum Motion: Sendable {
        /// Slides back and forth along `dir` by up to `amplitude`.
        case slide(dir: Vec, amplitude: Double)
        /// Swings about `pivot` by up to `amplitude` radians either side of the rest position.
        case swing(pivot: Vec, amplitude: Double)
    }
    var p0: Vec
    var p1: Vec
    var thickness: Double = 14
    var motion: Motion
    /// Radians per second.
    var speed: Double = 1.0
    var phase: Double = 0

    /// The two ends of the wall at a time.
    func ends(at time: Double) -> (a: Vec, b: Vec) {
        let s = sin(speed * time + phase)
        switch motion {
        case .slide(let dir, let amplitude):
            let off = dir * (amplitude * s)
            return (p0 + off, p1 + off)
        case .swing(let pivot, let amplitude):
            let angle = amplitude * s
            let c = cos(angle), sn = sin(angle)
            func turn(_ p: Vec) -> Vec {
                let d = p - pivot
                return pivot + Vec(d.x * c - d.y * sn, d.x * sn + d.y * c)
            }
            return (turn(p0), turn(p1))
        }
    }
}

/// A pressure pad on the floor. Rolling over it opens the door with the same number, for good.
nonisolated struct FloorSwitch: Sendable {
    var center: Vec
    var radius: Double = 17
}

/// A wall that is solid until its switch is pressed.
nonisolated struct Door: Sendable {
    var outline: [Vec]
}

/// A thin wall that a ball passes through coming from behind, but bounces off from the front.
nonisolated struct OneWay: Sendable {
    var a: Vec
    var b: Vec
    /// Points toward the side that blocks.
    var front: Vec
}

/// A springy bar: it kicks the ball away faster than it arrived.
nonisolated struct BouncePad: Sendable {
    var a: Vec
    var b: Vec
}

/// A block that shatters when hit hard enough, and is a plain wall when hit softly.
nonisolated struct Breakable: Sendable {
    var outline: [Vec]
    /// The speed into the block needed to break it.
    var breakSpeed: Double = 300
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
    var portals: [Portal]
    var movers: [Mover]
    var switches: [FloorSwitch]
    var doors: [Door]
    var oneWays: [OneWay]
    var bouncePads: [BouncePad]
    var breakables: [Breakable]
    var tee: Vec
    var cup: Vec
    var par: Int
    /// Whether anything on the hole moves with time (so the ball must be watched even at rest).
    var hasTimedObstacles: Bool { !windmills.isEmpty || !movers.isEmpty }
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
        portals: [Portal] = [],
        movers: [Mover] = [],
        switches: [FloorSwitch] = [],
        doors: [Door] = [],
        oneWays: [OneWay] = [],
        bouncePads: [BouncePad] = [],
        breakables: [Breakable] = [],
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
        self.portals = portals
        self.movers = movers
        self.switches = switches
        self.doors = doors
        self.oneWays = oneWays
        self.bouncePads = bouncePads
        self.breakables = breakables
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
