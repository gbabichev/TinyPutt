//
//  HoleGenerator.swift
//  Tiny Putt
//
//  Makes holes from a seed. A hole is a layout (a shape drawn around a "spine" from tee to cup),
//  a few obstacles placed along the spine, and a finish around the cup. Everything is a pure
//  function of (level, seed), so a hole looks and plays the same on every device. The offline
//  hole checker (Tools/HoleChecker) proves a seed makes a finishable, interesting hole before it
//  is allowed into `CampaignTable`.
//

import Foundation

// MARK: - Random numbers

/// SplitMix64: small, fast, and identical on every platform.
nonisolated struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
        _ = next()
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
    /// Inclusive.
    mutating func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(next() % UInt64(hi - lo + 1)) }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    mutating func sign() -> Double { chance(0.5) ? 1 : -1 }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0, items.count - 1)] }
}

// MARK: - The spine

nonisolated struct Frame {
    var pos: Vec
    var dir: Vec
    var width: Double
    var n: Vec { dir.perp }
    func at(along: Double, across: Double) -> Vec { pos + dir * along + dir.perp * across }
}

/// The line from tee to cup that a layout is drawn around, with a width at each point.
nonisolated struct Spine {
    let pts: [Vec]
    let widths: [Double]
    private let cum: [Double]
    var length: Double { cum.last ?? 0 }

    init(_ pts: [Vec], widths: [Double]) {
        self.pts = pts
        self.widths = widths
        var c = [0.0]
        for i in 1..<pts.count { c.append(c[i - 1] + pts[i].distance(to: pts[i - 1])) }
        cum = c
    }

    func frame(at s: Double) -> Frame {
        let d = max(0, min(length, s))
        var i = 1
        while i < pts.count - 1, cum[i] < d { i += 1 }
        let span = max(cum[i] - cum[i - 1], 1e-9)
        let t = (d - cum[i - 1]) / span
        let dir = (pts[i] - pts[i - 1]).normalized
        return Frame(pos: pts[i - 1] + (pts[i] - pts[i - 1]) * t, dir: dir, width: widths[i - 1] + (widths[i] - widths[i - 1]) * t)
    }

    /// A distance along the spine that is clear of its corners, so gadgets sit on straight ground.
    func clear(_ s: Double, margin: Double = 100) -> Double {
        var d = max(60, min(length - 60, s))
        for v in 1..<(pts.count - 1) {
            let corner = cum[v]
            if abs(d - corner) < margin { d = d < corner ? corner - margin : corner + margin }
        }
        return max(60, min(length - 60, d))
    }
}

// MARK: - Recipes

nonisolated enum Template: Int, CaseIterable, Sendable {
    case straight, waist, lShape, sBend, uTurn, diagonal, zigzag, room, arena
}

nonisolated enum Middle: Int, CaseIterable, Sendable {
    case gate, pillars, bar, sand, ice, mud, pond, lava, bumpers, windmill, magnet, wind, slope
    // The newer obstacles.
    case portal, tunnel, slider, pendulum, piston, spinner, boost, bridge, jump, oneWay, door, springBars, brickWall

    /// Obstacles that move with time. A hole has at most one kind, so a shot never has to beat two
    /// clocks at once.
    var isTimed: Bool { [.windmill, .slider, .pendulum, .piston, .spinner].contains(self) }
}

nonisolated enum Finale: Int, CaseIterable, Sendable {
    case plain, sandRing, waterFlanks, lavaFlanks, bumperGuard, backstop
}

nonisolated struct Generated {
    var hole: Hole
    var template: Template
    var middles: [Middle]
    var finale: Finale
}

nonisolated enum HoleGenerator {
    /// How hard a level is, from 1 (gentle) to 3. Levels 1-10 are hand-made, so this starts at 11.
    static func tier(forLevel level: Int) -> Int { level <= 25 ? 1 : level <= 38 ? 2 : 3 }

    /// Past the warm-up, difficulty climbs one step every 100 levels: 0 up to level 100, up to 9
    /// from level 901 on. Each step adds obstacles, narrows the course and (in the checker) asks for
    /// more strokes and a finer aim.
    static func step(forLevel level: Int) -> Int { level <= 50 ? 0 : min(9, (level - 1) / 100) }

    /// A new twist joins the mix every 25 levels from level 51, and stays on.
    enum Twist: Int, CaseIterable {
        case fourObstacles, moreDishes, windingCourses, twoClocks, fasterGadgets, moreHazards
    }

    static func has(_ twist: Twist, level: Int) -> Bool { level >= 51 + 25 * twist.rawValue }

    /// Builds the hole for a seed. Returns nil when the random layout came out unusable.
    static func make(level: Int, seed: UInt64, theme: ThemeID? = nil, par: Int = 3,
                     template forcedTemplate: Template? = nil, middle forcedMiddle: Middle? = nil) -> Generated? {
        var rng = SeededRandom(seed: seed &* 0x517C_C1B7_2722_0A95 &+ UInt64(level))
        let tier = tier(forLevel: level)

        let template = forcedTemplate ?? pickTemplate(tier: tier, level: level, rng: &rng)
        let step = step(forLevel: level)
        guard let layout = layout(for: template, squeeze: 1 - 0.02 * Double(step), rng: &rng) else { return nil }
        let spine = layout.spine
        var blocks: [[Vec]] = [], patches: [Patch] = []
        var bumpers: [Bumper] = [], windmills: [Windmill] = [], magnets: [Magnet] = []
        var portals: [Portal] = [], movers: [Mover] = [], switches: [FloorSwitch] = [], doors: [Door] = []
        var oneWays: [OneWay] = [], bouncePads: [BouncePad] = [], breakables: [Breakable] = []

        // Obstacles along the way.
        let middles = pickMiddles(tier: tier, step: step, level: level, width: spine.widths.min() ?? 100, first: forcedMiddle, rng: &rng)
        let first = spine.length * 0.30, last = spine.length * 0.70
        for (k, kind) in middles.enumerated() {
            let t = middles.count == 1 ? 0.5 : Double(k) / Double(middles.count - 1)
            let s = spine.clear(first + (last - first) * t + rng.range(-25, 25))
            var b = Builder(frame: spine.frame(at: s), tier: tier)
            b.place(kind, rng: &rng)
            if has(.fasterGadgets, level: level) {
                // Timed gadgets run a little quicker as the game goes on.
                let pace = 1 + 0.03 * Double(step)
                for i in b.movers.indices { b.movers[i].speed *= pace }
                for i in b.windmills.indices { b.windmills[i].speed *= pace }
            }
            blocks += b.blocks; patches += b.patches
            bumpers += b.bumpers; windmills += b.windmills; magnets += b.magnets
            portals += b.portals; movers += b.movers; switches += b.switches; doors += b.doors
            oneWays += b.oneWays; bouncePads += b.bouncePads; breakables += b.breakables
        }

        // Tee and cup, near the two ends of the spine.
        let teeFrame = spine.frame(at: 62)
        let cupFrame = spine.frame(at: spine.length - 62)
        let tee = teeFrame.pos + teeFrame.n * rng.range(-0.12, 0.12) * teeFrame.width
        let cup = cupFrame.pos + cupFrame.n * rng.range(-0.15, 0.15) * cupFrame.width

        let finale = pickFinale(tier: tier, level: level, width: cupFrame.width, rng: &rng)
        var fin = Builder(frame: Frame(pos: cup, dir: cupFrame.dir, width: cupFrame.width), tier: tier)
        fin.finish(finale, rng: &rng)
        blocks += fin.blocks; patches += fin.patches; bumpers += fin.bumpers

        // About one hole in three has the cup in a dish or on a hill. Decided from the seed, not
        // the random stream, so every other choice for a seed stays as it was.
        var bowls: [Bowl] = []
        let mix = seed &* 0x9E37_79B9_7F4A_7C15
        if mix >> 61 < (has(.moreDishes, level: level) ? 5 : 3) {
            let radius = min(125, max(85, cupFrame.width * 0.85))
            let hill = (mix >> 30) & 1 == 1
            bowls.append(Bowl(center: cup, radius: radius, strength: hill ? -330 : 340))
        }

        var hole = Hole(
            name: "Hole \(level)",
            theme: theme ?? .meadow,
            size: Vec(600, 900),
            outline: layout.outline,
            blocks: blocks, patches: patches, bumpers: bumpers, windmills: windmills, magnets: magnets, bowls: bowls,
            portals: portals, movers: movers, switches: switches, doors: doors, oneWays: oneWays,
            bouncePads: bouncePads, breakables: breakables,
            tee: tee, cup: cup, par: par
        )
        hole = randomlyTurned(hole, rng: &rng)
        guard isValid(hole) else { return nil }
        return Generated(hole: hole, template: template, middles: middles, finale: finale)
    }

    /// Worlds that suit a recipe, best first.
    static func themeCandidates(for g: Generated) -> [ThemeID] {
        var order: [ThemeID] = []
        if g.middles.contains(.ice) || g.middles.contains(.wind) { order.append(.winter) }
        if g.middles.contains(.sand) || g.middles.contains(.lava) || g.finale == .sandRing || g.finale == .lavaFlanks { order.append(.desert) }
        if g.middles.contains(.bumpers) || g.middles.contains(.magnet) || g.finale == .bumperGuard { order.append(.farm) }
        if g.middles.contains(.portal) || g.middles.contains(.tunnel) || g.middles.contains(.springBars) || g.middles.contains(.piston) { order.append(.farm) }
        if g.middles.contains(.bridge) || g.middles.contains(.jump) || g.middles.contains(.brickWall) { order.append(.desert) }
        order.append(.meadow)
        for t in ThemeID.allCases where !order.contains(t) { order.append(t) }
        return order
    }

    // MARK: Choosing

    /// The layouts a tier may use (the tight zigzag only appears once the game has warmed up).
    static func templates(tier: Int, level: Int = 0) -> [Template] {
        var pool: [Template] = [.straight, .waist, .lShape, .sBend, .uTurn, .diagonal, .room, .arena]
        if tier >= 2 { pool.append(.zigzag) }
        // Winding courses turn up more once that twist is on.
        if has(.windingCourses, level: level) { pool += [.zigzag, .sBend, .uTurn, .lShape] }
        return pool
    }

    private static func pickTemplate(tier: Int, level: Int, rng: inout SeededRandom) -> Template {
        rng.pick(templates(tier: tier, level: level))
    }

    private static func pickMiddles(tier: Int, step: Int, level: Int, width: Double, first: Middle?, rng: inout SeededRandom) -> [Middle] {
        let count: Int
        switch tier {
        case 1: count = 1
        case 2: count = rng.chance(0.55) ? 2 : 1
        default:
            if step == 0 {
                count = rng.chance(0.4) ? 3 : 2
            } else {
                // Every step makes a third obstacle likelier, and from step 3 a fourth can appear.
                count = 2 + (rng.chance(min(0.95, 0.4 + 0.1 * Double(step))) ? 1 : 0)
                    + (has(.fourObstacles, level: level) && rng.chance(0.15 + 0.06 * Double(step)) ? 1 : 0)
            }
        }
        var pool = Middle.allCases
        // Narrow courses cannot hold the big gadgets.
        if width < 150 { pool.removeAll { [.bar, .pillars].contains($0) } }
        if width < 115 { pool.removeAll { [.pendulum, .spinner, .slider, .springBars].contains($0) } }
        if width < 120 { pool.removeAll { [.windmill, .bumpers, .pond, .lava, .portal, .tunnel, .bridge, .jump, .piston].contains($0) } }
        var picked: [Middle] = []
        func take(_ m: Middle) {
            pool.removeAll { $0 == m }
            // Two floor surfaces next to each other turn into mush.
            if [.sand, .mud, .ice].contains(m) { pool.removeAll { [.sand, .mud, .ice].contains($0) } }
            // One clock per hole.
            // (Once the twist is on, a second clock is allowed now and then.)
            if m.isTimed, !(has(.twoClocks, level: level) && rng.chance(0.5)) { pool.removeAll { $0.isTimed } }
            // Rivers and walls with a trick are each used once.
            if [.bridge, .jump, .pond, .lava].contains(m) { pool.removeAll { [.bridge, .jump].contains($0) } }
            if [.portal, .tunnel].contains(m) { pool.removeAll { [.portal, .tunnel].contains($0) } }
            if [.door, .brickWall, .oneWay].contains(m) { pool.removeAll { [.door, .brickWall, .oneWay].contains($0) } }
            picked.append(m)
        }
        if let first, pool.contains(first) { take(first) }
        let wanted = step >= 6 ? max(count, 3) : count
        while picked.count < min(wanted, 4), !pool.isEmpty {
            take(rng.pick(pool))
        }
        return picked
    }

    private static func pickFinale(tier: Int, level: Int, width: Double, rng: inout SeededRandom) -> Finale {
        var pool: [Finale] = [.plain, .plain, .sandRing, .backstop, .bumperGuard]
        if has(.moreHazards, level: level), width >= 150 { pool += [.waterFlanks, .lavaFlanks] }
        if width >= 150 { pool += [.waterFlanks]; if tier >= 2 { pool.append(.lavaFlanks) } }
        return rng.pick(pool)
    }

    // MARK: Layouts

    private struct Layout {
        var spine: Spine
        var outline: [Vec]
    }

    /// The outline of a thick path: a band around the spine, with mitred corners.
    private static func band(_ spine: Spine, radius: Double) -> [Vec] {
        var left: [Vec] = [], right: [Vec] = []
        let p = spine.pts, w = spine.widths
        for i in 0..<p.count {
            let half = w[i] / 2
            var offset: Vec
            if i == 0 {
                offset = (p[1] - p[0]).normalized.perp * half
            } else if i == p.count - 1 {
                offset = (p[i] - p[i - 1]).normalized.perp * half
            } else {
                let n0 = (p[i] - p[i - 1]).normalized.perp, n1 = (p[i + 1] - p[i]).normalized.perp
                let m = (n0 + n1).normalized
                offset = m * (half / max(0.4, m.dot(n0)))
            }
            left.append(p[i] + offset)
            right.append(p[i] - offset)
        }
        return Poly.rounded(left + right.reversed(), radius: radius)
    }

    private static func layout(for template: Template, squeeze: Double, rng: inout SeededRandom) -> Layout? {
        let cx = 300.0
        /// A spine whose widths are narrowed by the difficulty step.
        func narrowed(_ pts: [Vec], widths: [Double]) -> Spine {
            Spine(pts, widths: widths.map { $0 * squeeze })
        }
        switch template {
        case .straight:
            let x = cx + rng.range(-30, 30)
            let w0 = rng.range(120, 190), w1 = rng.range(120, 190)
            let spine = narrowed([Vec(x, 790), Vec(x, 130)], widths: [w0, w1])
            return Layout(spine: spine, outline: band(spine, radius: 30))
        case .waist:
            let x = cx + rng.range(-20, 20)
            let wide = rng.range(170, 230), narrow = rng.range(100, 130)
            let spine = narrowed([Vec(x, 790), Vec(x, 540), Vec(x, 380), Vec(x, 130)], widths: [wide, narrow, narrow, wide * rng.range(0.8, 1)])
            return Layout(spine: spine, outline: band(spine, radius: 34))
        case .lShape:
            let x0 = rng.range(180, 240), y1 = rng.range(190, 260)
            let w = rng.range(120, 160)
            let spine = narrowed([Vec(x0, 790), Vec(x0, y1), Vec(x0 + rng.range(200, 270), y1)], widths: [w, w, w])
            return Layout(spine: spine, outline: band(spine, radius: 28))
        case .sBend:
            let xa = rng.range(180, 220), xb = rng.range(380, 420)
            let y1 = rng.range(430, 530)
            let w = rng.range(120, 150)
            let spine = narrowed([Vec(xa, 790), Vec(xa, y1), Vec(xb, y1 - rng.range(0, 40)), Vec(xb, 130)], widths: [w, w, w, w])
            return Layout(spine: spine, outline: band(spine, radius: 26))
        case .uTurn:
            let xa = rng.range(160, 190), xb = rng.range(410, 440)
            let w = rng.range(105, 135)
            let top = rng.range(180, 230)
            let spine = narrowed([Vec(xa, 760), Vec(xa, top), Vec(xb, top), Vec(xb, rng.range(560, 680))], widths: [w, w, w, w])
            return Layout(spine: spine, outline: band(spine, radius: 24))
        case .diagonal:
            let w = rng.range(125, 165)
            let spine = narrowed([Vec(150, 770), Vec(450, 150)], widths: [w, w])
            return Layout(spine: spine, outline: band(spine, radius: 30))
        case .zigzag:
            let w = rng.range(105, 125)
            let spine = narrowed([Vec(170, 780), Vec(430, 560), Vec(170, 340), Vec(430, 130)], widths: [w, w, w, w])
            return Layout(spine: spine, outline: band(spine, radius: 22))
        case .room:
            let w = rng.range(300, 400), h = rng.range(500, 620)
            let x = cx - w / 2, y = 450 - h / 2
            let outline = Poly.rounded(Poly.rect(x, y, w, h), radius: rng.range(40, 110))
            let spine = Spine([Vec(cx, y + h), Vec(cx, y)], widths: [w, w])
            return Layout(spine: spine, outline: outline)
        case .arena:
            let rx = rng.range(190, 250), ry = rng.range(290, 350)
            let outline = Poly.ellipse(Vec(cx, 450), rx, ry, steps: 64)
            let spine = Spine([Vec(cx, 450 + ry - 20), Vec(cx, 450 - ry + 20)], widths: [rx * 1.2, rx * 1.2])
            return Layout(spine: spine, outline: outline)
        }
    }

    // MARK: Checks and turning

    /// Random mirror and quarter turn, so the same shape reads differently.
    private static func randomlyTurned(_ hole: Hole, rng: inout SeededRandom) -> Hole {
        var h = hole
        if rng.chance(0.5) {
            let w = h.size.x
            h = h.mapped(size: h.size, point: { Vec(w - $0.x, $0.y) }, vector: { Vec(-$0.x, $0.y) })
        }
        if rng.chance(0.35) {
            h = h.mapped(size: Vec(h.size.y, h.size.x), point: { Vec($0.y, $0.x) }, vector: { Vec($0.y, $0.x) })
        }
        return h
    }

    /// The basics every hole must have, whatever the checker thinks of it.
    static func isValid(_ h: Hole) -> Bool {
        guard isSimple(h.outline) else { return false }
        let b = Poly.bounds(h.outline)
        guard b.lo.x > 20, b.lo.y > 20, b.hi.x < h.size.x - 20, b.hi.y < h.size.y - 20 else { return false }
        for p in [h.tee, h.cup] {
            guard Poly.contains(h.outline, p) else { return false }
            for s in h.segments where Poly.closestPoint(s.a, s.b, to: p).distance(to: p) < 26 { return false }
            for patch in h.patches {
                switch patch.kind {
                case .water, .lava:
                    for off in [Vec.zero, Vec(30, 0), Vec(-30, 0), Vec(0, 30), Vec(0, -30)] where patch.contains(p + off) { return false }
                case .ramp, .boost:
                    // A ball must not be set off just by being put down, or by a tap from the tee.
                    for off in [Vec.zero, Vec(22, 0), Vec(-22, 0), Vec(0, 22), Vec(0, -22), Vec(44, 0), Vec(-44, 0), Vec(0, 44), Vec(0, -44)] where patch.contains(p + off) { return false }
                default: break
                }
            }
            for bm in h.bumpers where bm.center.distance(to: p) < bm.radius + 34 { return false }
            for w in h.windmills where w.center.distance(to: p) < w.length + 30 { return false }
            for m in h.magnets where m.center.distance(to: p) < 40 { return false }
            for pt in h.portals where pt.a.distance(to: p) < 55 || pt.b.distance(to: p) < 55 { return false }
            for sw in h.switches where sw.center.distance(to: p) < 45 { return false }
            for bar in h.bouncePads where Poly.closestPoint(bar.a, bar.b, to: p).distance(to: p) < 40 { return false }
            for m in h.movers where Poly.closestPoint(m.p0, m.p1, to: p).distance(to: p) < 50 { return false }
        }
        return h.tee.distance(to: h.cup) > 260
    }

    /// No two edges of the polygon cross.
    static func isSimple(_ poly: [Vec]) -> Bool {
        let n = poly.count
        func cross(_ a: Vec, _ b: Vec, _ c: Vec) -> Double { (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) }
        for i in 0..<n {
            let a = poly[i], b = poly[(i + 1) % n]
            guard i + 2 < n else { continue }
            for j in (i + 2)..<n where !(i == 0 && j == n - 1) {
                let c = poly[j], d = poly[(j + 1) % n]
                if (cross(a, b, c) > 0) != (cross(a, b, d) > 0), (cross(c, d, a) > 0) != (cross(c, d, b) > 0) { return false }
            }
        }
        return true
    }
}

// MARK: - Obstacles

/// Puts gadgets on the ground around one spot of the spine. Positions are given along the spine
/// (`along`) and across it (`across`), so they follow whatever way the hole is turned.
private nonisolated struct Builder {
    var frame: Frame
    var tier: Int
    var blocks: [[Vec]] = []
    var patches: [Patch] = []
    var bumpers: [Bumper] = []
    var windmills: [Windmill] = []
    var magnets: [Magnet] = []
    var portals: [Portal] = []
    var movers: [Mover] = []
    var switches: [FloorSwitch] = []
    var doors: [Door] = []
    var oneWays: [OneWay] = []
    var bouncePads: [BouncePad] = []
    var breakables: [Breakable] = []

    init(frame: Frame, tier: Int) {
        self.frame = frame
        self.tier = tier
    }

    private var w: Double { frame.width }

    private func rect(_ a0: Double, _ a1: Double, _ c0: Double, _ c1: Double, round: Double = 0) -> [Vec] {
        let pts = [frame.at(along: a0, across: c0), frame.at(along: a1, across: c0), frame.at(along: a1, across: c1), frame.at(along: a0, across: c1)]
        return Poly.rounded(pts, radius: round)
    }

    /// A rounded pool shape: an ellipse with a gentle wobble so it looks natural, not stamped.
    private func ellipse(along: Double, across: Double, a: Double, b: Double) -> [Vec] {
        let phase = along * 0.07 + across * 0.031
        return (0..<40).map { i in
            let t = Double(i) / 40 * 2 * .pi
            let wobble = 1 + 0.09 * sin(2 * t + phase) + 0.05 * sin(3 * t - phase * 1.3)
            return frame.at(along: along + cos(t) * a * wobble, across: across + sin(t) * b * wobble)
        }
    }

    // A pond or lava lake that leaves a lane of `lane` along one side.
    private mutating func lake(_ kind: SurfaceKind, side: Double, lane: Double, along: Double, a: Double) {
        // The lake sits against one wall and reaches toward the middle, leaving a lane. It is never
        // wider than it is reasonable for a pool, and never a long thin oval.
        let wall = side * (-w / 2 - 14)
        let reach = min(w - lane + 14, 200)
        guard reach > 40 else { return }
        let b = reach / 2
        let alongRadius = min(max(a, b * 0.78), b * 1.4)
        let centre = wall + side * b
        patches.append(Patch(kind, ellipse(along: along, across: centre, a: alongRadius, b: b)))
    }

    // Two lakes, one on each flank, leaving a channel down the middle.
    private mutating func flanks(_ kind: SurfaceKind, channel: Double, along: Double, a: Double) {
        let full = (w / 2 + 14 - channel) / 2
        let hb = min(full, 85)
        guard hb > 14 else { return }
        let alongRadius = min(max(a, hb * 0.8), hb * 1.4)
        for side in [-1.0, 1.0] {
            patches.append(Patch(kind, ellipse(along: along, across: side * (w / 2 + 14 - hb), a: alongRadius, b: hb)))
        }
    }

    mutating func place(_ kind: Middle, rng: inout SeededRandom) {
        let hard = tier >= 3
        switch kind {
        case .gate:
            let g = rng.range(hard ? 56 : 66, 96)
            let lim = w / 2 - g / 2 - 24
            guard lim > 4 else { return }
            let o = rng.range(-lim, lim)
            blocks.append(rect(-13, 13, -w / 2 - 14, o - g / 2, round: 5))
            blocks.append(rect(-13, 13, o + g / 2, w / 2 + 14, round: 5))
        case .pillars:
            let size = rng.range(30, 44)
            let count = min(rng.int(1, 3), Int((w - 56) / (size + 56)))
            guard count >= 1 else { return }
            let gap = (w - Double(count) * size) / Double(count + 1)
            for k in 0..<count {
                let across = -w / 2 + gap * Double(k + 1) + size * (Double(k) + 0.5)
                let along = (k.isMultiple(of: 2) ? 1.0 : -1.0) * rng.range(0, 40)
                blocks.append(rect(along - size / 2, along + size / 2, across - size / 2, across + size / 2, round: 7))
            }
        case .bar:
            guard w >= 160 else { return }
            let len = rng.range(130, 210), off = rng.range(-w * 0.08, w * 0.08)
            blocks.append(rect(-len / 2, len / 2, off - 12, off + 12, round: 10))
        case .sand, .mud:
            let kindOut: SurfaceKind = kind == .sand ? .sand : .mud
            if rng.chance(0.3) {
                patches.append(Patch(kindOut, Poly.rounded(rect(-rng.range(40, 70), rng.range(40, 70), -w / 2 - 14, w / 2 + 14), radius: 14)))
            } else {
                let o = rng.range(-w * 0.2, w * 0.2)
                let b = min(w * rng.range(0.38, 0.6), 105)
                patches.append(Patch(kindOut, ellipse(along: 0, across: o, a: max(rng.range(50, 90), b * 0.7), b: b)))
            }
        case .ice:
            let len = rng.range(110, 190)
            patches.append(Patch(.ice, Poly.rounded(rect(-len / 2, len / 2, -w / 2 - 14, w / 2 + 14), radius: 10)))
        case .pond:
            if w >= 150, rng.chance(0.5) {
                flanks(.water, channel: rng.range(36, 48), along: rng.range(-20, 20), a: rng.range(32, 52))
            } else {
                lake(.water, side: rng.sign(), lane: rng.range(70, 92), along: 0, a: rng.range(40, 62))
            }
        case .lava:
            let side = rng.sign()
            let gap = rng.range(55, 75)
            lake(.lava, side: side, lane: rng.range(72, 90), along: -gap, a: rng.range(38, 54))
            lake(.lava, side: -side, lane: rng.range(72, 90), along: gap, a: rng.range(38, 54))
        case .bumpers:
            guard w >= 110 else { return }
            let target = tier >= 2 ? rng.int(3, 4) : rng.int(2, 3)
            var placed: [Vec] = []
            var tries = 0
            while placed.count < target, tries < 30 {
                tries += 1
                let r = rng.range(17, 24)
                let across = rng.range(-(w / 2 - r - 22), w / 2 - r - 22), along = rng.range(-65, 65)
                let p = frame.at(along: along, across: across)
                if placed.allSatisfy({ $0.distance(to: p) > 60 }) {
                    placed.append(p)
                    bumpers.append(Bumper(center: p, radius: r))
                }
            }
        case .windmill:
            guard w >= 120 else { return }
            let blades = rng.chance(0.7) ? 4 : 3
            magnetsAndWindmill(Windmill(center: frame.pos, length: min(w * 0.5 + 12, 118), blades: blades,
                                        speed: rng.range(0.8, 1.3) * rng.sign(), phase: rng.range(0, 6.28)))
        case .magnet:
            if rng.chance(0.55) {
                magnets.append(Magnet(center: frame.at(along: 0, across: rng.sign() * w * 0.22), radius: rng.range(120, 150), strength: rng.range(600, 800)))
            } else {
                magnets.append(Magnet(center: frame.pos, radius: 100, strength: -rng.range(600, 800)))
            }
        case .wind:
            let len = rng.range(140, 220)
            let accel = rng.chance(0.6) ? frame.n * (rng.sign() * rng.range(180, 260)) : frame.dir * (rng.sign() * rng.range(140, 200))
            patches.append(Patch(.wind(accel), Poly.rounded(rect(-len / 2, len / 2, -w / 2 - 14, w / 2 + 14), radius: 12)))
        case .slope:
            let len = rng.range(120, 200)
            let accel = rng.chance(0.6) ? frame.dir * (rng.sign() * rng.range(120, 170)) : frame.n * (rng.sign() * rng.range(120, 160))
            patches.append(Patch(.slope(accel), Poly.rounded(rect(-len / 2, len / 2, -w / 2 - 14, w / 2 + 14), radius: 12)))
        case .portal, .tunnel:
            guard w >= 110 else { return }
            let tunnel = kind == .tunnel
            // A solid wall across the whole course: the only way on is through the openings.
            blocks.append(rect(-7, 7, -w / 2 - 14, w / 2 + 14, round: 4))
            let lim = max(8, w / 2 - 32)
            let reach = tunnel ? rng.range(80, 110) : rng.range(70, 90)
            let a = frame.at(along: -reach, across: rng.range(-lim, lim))
            let b = frame.at(along: reach, across: rng.range(-lim, lim))
            portals.append(Portal(a: a, b: b, radius: 15, delay: tunnel ? 0.45 : 0))
        case .slider:
            guard w >= 115 else { return }
            let length = w * 0.55
            let amp = (w - length) / 2 - 5
            movers.append(Mover(p0: frame.at(along: 0, across: -length / 2), p1: frame.at(along: 0, across: length / 2),
                                thickness: 14, motion: .slide(dir: frame.n, amplitude: amp),
                                speed: rng.range(0.9, 1.4), phase: rng.range(0, 6.28)))
        case .pendulum:
            guard w >= 115 else { return }
            let side = rng.sign()
            let pivot = frame.at(along: 0, across: side * (w / 2 + 8))
            let tip = frame.at(along: 0, across: side * (w / 2 + 8) - side * (w * 0.9))
            movers.append(Mover(p0: pivot, p1: tip, thickness: 12, motion: .swing(pivot: pivot, amplitude: rng.range(0.85, 1.1)),
                                speed: rng.range(0.9, 1.3), phase: rng.range(0, 6.28)))
        case .piston:
            guard w >= 120 else { return }
            let len = 36.0, depth = w * 0.27, amp = w * 0.2
            let speed = rng.range(1.0, 1.5)
            let base = rng.range(0, 6.28)
            for (k, side) in [-1.0, 1.0].enumerated() {
                let along = side * 24
                let wall = side * (w / 2 + 14)
                let inward = -side
                let tip = frame.at(along: along, across: wall + inward * depth)
                let tail = frame.at(along: along, across: wall + inward * (depth - len))
                movers.append(Mover(p0: tail, p1: tip, thickness: 22, motion: .slide(dir: frame.n * inward, amplitude: amp),
                                    speed: speed, phase: base + Double(k) * .pi))
            }
        case .spinner:
            guard w >= 115 else { return }
            let length = min(w * 0.36, 70)
            windmills.append(Windmill(style: .spinner, center: frame.pos, length: length, blades: 2,
                                      speed: rng.range(1.7, 2.4) * rng.sign(), phase: rng.range(0, 6.28), hub: 10, thickness: 9))
        case .boost:
            let full = rng.chance(0.5)
            let span = full ? w + 28 : w * 0.5
            let o = full ? 0 : rng.range(-(w / 2 - span / 2 - 6), w / 2 - span / 2 - 6)
            let dir = rng.chance(0.8) ? frame.dir : frame.n * rng.sign()
            patches.append(Patch(.boost(dir), Poly.rounded(rect(-20, 20, o - span / 2, o + span / 2), radius: 8)))
        case .bridge:
            guard w >= 110 else { return }
            let river: SurfaceKind = (tier >= 2 && rng.chance(0.4)) ? .lava : .water
            patches.append(Patch(river, Poly.rounded(rect(-34, 34, -w / 2 - 14, w / 2 + 14), radius: 12)))
            let o = rng.range(-(w / 2 - 38), w / 2 - 38)
            patches.append(Patch(.bridge, rect(-42, 42, o - 24, o + 24)))
            // A rail down each side keeps a ball on the bridge once it is on it.
            blocks.append(rect(-34, 34, o - 29, o - 24, round: 2))
            blocks.append(rect(-34, 34, o + 24, o + 29, round: 2))
        case .jump:
            guard w >= 110 else { return }
            // The ramp is in front of the river, so move the whole thing on a little to keep the
            // ramp well clear of the tee.
            frame.pos = frame.pos + frame.dir * 46
            patches.append(Patch(.water, Poly.rounded(rect(-45, 45, -w / 2 - 14, w / 2 + 14), radius: 12)))
            patches.append(Patch(.ramp(frame.dir), Poly.rounded(rect(-78, -50, -w / 2 - 14, w / 2 + 14), radius: 6)))
        case .oneWay:
            guard w >= 100 else { return }
            let g = rng.range(56, 72)
            let lim = w / 2 - g / 2 - 14
            guard lim > 2 else { return }
            let o = rng.range(-lim, lim)
            blocks.append(rect(-7, 7, -w / 2 - 14, o - g / 2, round: 4))
            blocks.append(rect(-7, 7, o + g / 2, w / 2 + 14, round: 4))
            oneWays.append(OneWay(a: frame.at(along: 0, across: o - g / 2), b: frame.at(along: 0, across: o + g / 2), front: frame.dir))
        case .door:
            guard w >= 100 else { return }
            doors.append(Door(outline: rect(-7, 7, -w / 2 - 14, w / 2 + 14, round: 3)))
            let lim = max(6, w / 2 - 26)
            switches.append(FloorSwitch(center: frame.at(along: -rng.range(55, 85), across: rng.range(-lim, lim)), radius: 17))
        case .springBars:
            guard w >= 110 else { return }
            for (k, side) in [-1.0, 1.0].enumerated() {
                let a = frame.at(along: (k == 0 ? -34 : 34), across: side * (w / 2 + 8))
                let b = a + frame.n * (-side * w * 0.36) + frame.dir * 22
                bouncePads.append(BouncePad(a: a, b: b))
            }
        case .brickWall:
            guard w >= 100 else { return }
            let parts = 3
            let span = (w + 28) / Double(parts)
            for k in 0..<parts {
                let c0 = -w / 2 - 14 + span * Double(k)
                breakables.append(Breakable(outline: rect(-8, 8, c0 + 1, c0 + span - 1, round: 3), breakSpeed: 300))
            }
        }
    }

    private mutating func magnetsAndWindmill(_ wm: Windmill) { windmills.append(wm) }

    /// The ground around the cup. `frame.pos` is the cup.
    mutating func finish(_ kind: Finale, rng: inout SeededRandom) {
        switch kind {
        case .plain: break
        case .sandRing:
            patches.append(Patch(.sand, ellipse(along: 0, across: 0, a: rng.range(48, 62), b: rng.range(48, 62))))
        case .waterFlanks:
            flanks(.water, channel: 40, along: 0, a: rng.range(34, 48))
        case .lavaFlanks:
            flanks(.lava, channel: 42, along: 0, a: rng.range(32, 44))
        case .bumperGuard:
            for side in [-1.0, 1.0] { bumpers.append(Bumper(center: frame.at(along: 46, across: side * 34), radius: 18)) }
        case .backstop:
            blocks.append(rect(46, 64, -44, 44, round: 8))
        }
    }
}

// MARK: - Mirroring and turning a hole

nonisolated extension Hole {
    /// The same hole seen through a mirror or a quarter turn (given as how points and vectors move).
    func mapped(size: Vec, point: (Vec) -> Vec, vector: (Vec) -> Vec) -> Hole {
        let newPatches = patches.map { patch -> Patch in
            var kind = patch.kind
            switch kind {
            case .slope(let v): kind = .slope(vector(v))
            case .wind(let v): kind = .wind(vector(v))
            case .boost(let v): kind = .boost(vector(v))
            case .ramp(let v): kind = .ramp(vector(v))
            default: break
            }
            return Patch(kind, patch.outline.map(point))
        }
        var wm = windmills
        for i in wm.indices { wm[i].center = point(wm[i].center) }
        var mg = magnets
        for i in mg.indices { mg[i].center = point(mg[i].center) }
        var bm = bumpers
        for i in bm.indices { bm[i].center = point(bm[i].center) }
        var bw = bowls
        for i in bw.indices { bw[i].center = point(bw[i].center) }
        return Hole(
            name: name, theme: theme, size: size,
            outline: outline.map(point), blocks: blocks.map { $0.map(point) },
            patches: newPatches, bumpers: bm, windmills: wm, magnets: mg, bowls: bw,
            portals: portals.map { Portal(a: point($0.a), b: point($0.b), radius: $0.radius, delay: $0.delay) },
            movers: movers.map { m in
                // A mirror or a quarter turn reverses which way round things swing.
                let motion: Mover.Motion
                switch m.motion {
                case .slide(let dir, let amplitude): motion = .slide(dir: vector(dir), amplitude: amplitude)
                case .swing(let pivot, let amplitude): motion = .swing(pivot: point(pivot), amplitude: -amplitude)
                }
                return Mover(p0: point(m.p0), p1: point(m.p1), thickness: m.thickness, motion: motion, speed: m.speed, phase: m.phase)
            },
            switches: switches.map { FloorSwitch(center: point($0.center), radius: $0.radius) },
            doors: doors.map { Door(outline: $0.outline.map(point)) },
            oneWays: oneWays.map { OneWay(a: point($0.a), b: point($0.b), front: vector($0.front)) },
            bouncePads: bouncePads.map { BouncePad(a: point($0.a), b: point($0.b)) },
            breakables: breakables.map { Breakable(outline: $0.outline.map(point), breakSpeed: $0.breakSpeed) },
            tee: point(tee), cup: point(cup), par: par
        )
    }
}
