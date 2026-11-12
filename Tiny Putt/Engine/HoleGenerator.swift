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

    /// Builds the hole for a seed. Returns nil when the random layout came out unusable.
    static func make(level: Int, seed: UInt64, theme: ThemeID? = nil, par: Int = 3,
                     template forcedTemplate: Template? = nil, middle forcedMiddle: Middle? = nil) -> Generated? {
        var rng = SeededRandom(seed: seed &* 0x517C_C1B7_2722_0A95 &+ UInt64(level))
        let tier = tier(forLevel: level)

        let template = forcedTemplate ?? pickTemplate(tier: tier, rng: &rng)
        guard let layout = layout(for: template, rng: &rng) else { return nil }
        let spine = layout.spine
        var blocks: [[Vec]] = [], patches: [Patch] = []
        var bumpers: [Bumper] = [], windmills: [Windmill] = [], magnets: [Magnet] = []

        // Obstacles along the way.
        let middles = pickMiddles(tier: tier, width: spine.widths.min() ?? 100, first: forcedMiddle, rng: &rng)
        let first = spine.length * 0.30, last = spine.length * 0.70
        for (k, kind) in middles.enumerated() {
            let t = middles.count == 1 ? 0.5 : Double(k) / Double(middles.count - 1)
            let s = spine.clear(first + (last - first) * t + rng.range(-25, 25))
            var b = Builder(frame: spine.frame(at: s), tier: tier)
            b.place(kind, rng: &rng)
            blocks += b.blocks; patches += b.patches
            bumpers += b.bumpers; windmills += b.windmills; magnets += b.magnets
        }

        // Tee and cup, near the two ends of the spine.
        let teeFrame = spine.frame(at: 62)
        let cupFrame = spine.frame(at: spine.length - 62)
        let tee = teeFrame.pos + teeFrame.n * rng.range(-0.12, 0.12) * teeFrame.width
        let cup = cupFrame.pos + cupFrame.n * rng.range(-0.15, 0.15) * cupFrame.width

        let finale = pickFinale(tier: tier, width: cupFrame.width, rng: &rng)
        var fin = Builder(frame: Frame(pos: cup, dir: cupFrame.dir, width: cupFrame.width), tier: tier)
        fin.finish(finale, rng: &rng)
        blocks += fin.blocks; patches += fin.patches; bumpers += fin.bumpers

        // About one hole in three has the cup in a dish. Decided from the seed, not the random
        // stream, so every other choice for a seed stays as it was.
        var bowls: [Bowl] = []
        if (seed &* 0x9E37_79B9_7F4A_7C15) >> 61 < 3 {
            bowls.append(Bowl(center: cup, radius: min(125, max(85, cupFrame.width * 0.85))))
        }

        var hole = Hole(
            name: "Hole \(level)",
            theme: theme ?? .meadow,
            size: Vec(600, 900),
            outline: layout.outline,
            blocks: blocks, patches: patches, bumpers: bumpers, windmills: windmills, magnets: magnets, bowls: bowls,
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
        order.append(.meadow)
        for t in ThemeID.allCases where !order.contains(t) { order.append(t) }
        return order
    }

    // MARK: Choosing

    /// The layouts a tier may use (the tight zigzag only appears once the game has warmed up).
    static func templates(tier: Int) -> [Template] {
        var pool: [Template] = [.straight, .waist, .lShape, .sBend, .uTurn, .diagonal, .room, .arena]
        if tier >= 2 { pool.append(.zigzag) }
        return pool
    }

    private static func pickTemplate(tier: Int, rng: inout SeededRandom) -> Template {
        rng.pick(templates(tier: tier))
    }

    private static func pickMiddles(tier: Int, width: Double, first: Middle?, rng: inout SeededRandom) -> [Middle] {
        let count: Int
        switch tier {
        case 1: count = 1
        case 2: count = rng.chance(0.55) ? 2 : 1
        default: count = rng.chance(0.4) ? 3 : 2
        }
        var pool = Middle.allCases
        // Narrow courses cannot hold the big gadgets.
        if width < 150 { pool.removeAll { $0 == .bar || $0 == .pillars } }
        if width < 120 { pool.removeAll { $0 == .windmill || $0 == .bumpers || $0 == .pond || $0 == .lava } }
        var picked: [Middle] = []
        if let first, pool.contains(first) {
            pool.removeAll { $0 == first }
            if [.sand, .mud, .ice].contains(first) { pool.removeAll { [.sand, .mud, .ice].contains($0) } }
            picked.append(first)
        }
        while picked.count < min(count, 3), !pool.isEmpty {
            let m = rng.pick(pool)
            pool.removeAll { $0 == m }
            // Two floor surfaces next to each other turn into mush.
            if [.sand, .mud, .ice].contains(m) { pool.removeAll { [.sand, .mud, .ice].contains($0) } }
            picked.append(m)
        }
        return picked
    }

    private static func pickFinale(tier: Int, width: Double, rng: inout SeededRandom) -> Finale {
        var pool: [Finale] = [.plain, .plain, .sandRing, .backstop, .bumperGuard]
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

    private static func layout(for template: Template, rng: inout SeededRandom) -> Layout? {
        let cx = 300.0
        switch template {
        case .straight:
            let x = cx + rng.range(-30, 30)
            let w0 = rng.range(120, 190), w1 = rng.range(120, 190)
            let spine = Spine([Vec(x, 790), Vec(x, 130)], widths: [w0, w1])
            return Layout(spine: spine, outline: band(spine, radius: 30))
        case .waist:
            let x = cx + rng.range(-20, 20)
            let wide = rng.range(170, 230), narrow = rng.range(100, 130)
            let spine = Spine([Vec(x, 790), Vec(x, 540), Vec(x, 380), Vec(x, 130)], widths: [wide, narrow, narrow, wide * rng.range(0.8, 1)])
            return Layout(spine: spine, outline: band(spine, radius: 34))
        case .lShape:
            let x0 = rng.range(180, 240), y1 = rng.range(190, 260)
            let w = rng.range(120, 160)
            let spine = Spine([Vec(x0, 790), Vec(x0, y1), Vec(x0 + rng.range(200, 270), y1)], widths: [w, w, w])
            return Layout(spine: spine, outline: band(spine, radius: 28))
        case .sBend:
            let xa = rng.range(180, 220), xb = rng.range(380, 420)
            let y1 = rng.range(430, 530)
            let w = rng.range(120, 150)
            let spine = Spine([Vec(xa, 790), Vec(xa, y1), Vec(xb, y1 - rng.range(0, 40)), Vec(xb, 130)], widths: [w, w, w, w])
            return Layout(spine: spine, outline: band(spine, radius: 26))
        case .uTurn:
            let xa = rng.range(160, 190), xb = rng.range(410, 440)
            let w = rng.range(105, 135)
            let top = rng.range(180, 230)
            let spine = Spine([Vec(xa, 760), Vec(xa, top), Vec(xb, top), Vec(xb, rng.range(560, 680))], widths: [w, w, w, w])
            return Layout(spine: spine, outline: band(spine, radius: 24))
        case .diagonal:
            let w = rng.range(125, 165)
            let spine = Spine([Vec(150, 770), Vec(450, 150)], widths: [w, w])
            return Layout(spine: spine, outline: band(spine, radius: 30))
        case .zigzag:
            let w = rng.range(105, 125)
            let spine = Spine([Vec(170, 780), Vec(430, 560), Vec(170, 340), Vec(430, 130)], widths: [w, w, w, w])
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
                default: break
                }
            }
            for bm in h.bumpers where bm.center.distance(to: p) < bm.radius + 34 { return false }
            for w in h.windmills where w.center.distance(to: p) < w.length + 30 { return false }
            for m in h.magnets where m.center.distance(to: p) < 40 { return false }
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
            tee: point(tee), cup: point(cup), par: par
        )
    }
}
