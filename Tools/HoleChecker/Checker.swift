//
//  Checker.swift
//  HoleChecker
//
//  Plays a hole with the real game physics and decides whether it is worth shipping: can it be
//  finished, in how many strokes, how forgiving is the winning shot, can a ball get stuck, and
//  does it look like a hole we already have.
//

import Foundation

struct Attempt {
    var angle: Double
    var speed: Double
    /// When the shot starts, which matters for windmills.
    var offset: Double
}

enum Outcome {
    case sank, hazard
    case rest(Vec)
}

struct Report {
    var optimal: Int?
    /// How much of a small neighbourhood of the winning shot still sinks (0...1).
    var window = 0.0
    /// The share of shots from the tee that end in water or lava.
    var hazardRate = 0.0
    /// The share of early resting places the ball cannot get away from.
    var trapRate = 0.0
    var sims = 0
    /// The winning shots, in order: where each is played from.
    var solution: [(from: Vec, shot: Attempt)] = []
}

/// How far each spot is from the cup by walking around the walls.
struct DistanceField {
    let origin: Vec
    let cols: Int, rows: Int
    let cell = 12.0
    var dist: [Float]

    init(_ hole: Hole) {
        origin = Vec(0, 0)
        cols = Int(hole.size.x / 12) + 1
        rows = Int(hole.size.y / 12) + 1
        dist = [Float](repeating: .infinity, count: cols * rows)
        var free = [Bool](repeating: false, count: cols * rows)
        for cy in 0..<rows {
            for cx in 0..<cols {
                let p = Vec((Double(cx) + 0.5) * 12, (Double(cy) + 0.5) * 12)
                guard Poly.contains(hole.outline, p) else { continue }
                var ok = true
                for s in hole.segments where Poly.closestPoint(s.a, s.b, to: p).distance(to: p) < 9 { ok = false; break }
                if ok {
                    for patch in hole.patches {
                        if case .water = patch.kind, patch.contains(p) { ok = false }
                        if case .lava = patch.kind, patch.contains(p) { ok = false }
                    }
                }
                free[cy * cols + cx] = ok
            }
        }
        let start = index(of: hole.cup)
        free[start] = true
        dist[start] = 0
        var queue = [start], head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let cx = i % cols, cy = i / cols
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, nx < cols, ny >= 0, ny < rows else { continue }
                let j = ny * cols + nx
                if free[j], dist[j] == .infinity { dist[j] = dist[i] + 12; queue.append(j) }
            }
        }
    }

    func index(of p: Vec) -> Int {
        let cx = max(0, min(cols - 1, Int(p.x / cell))), cy = max(0, min(rows - 1, Int(p.y / cell)))
        return cy * cols + cx
    }

    func at(_ p: Vec) -> Double { Double(dist[index(of: p)]) }

    /// A point a little way along the walking route to the cup.
    func waypoint(from p: Vec, steps: Int) -> Vec {
        var cx = max(0, min(cols - 1, Int(p.x / cell))), cy = max(0, min(rows - 1, Int(p.y / cell)))
        for _ in 0..<steps {
            var best = dist[cy * cols + cx], bx = cx, by = cy
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, nx < cols, ny >= 0, ny < rows else { continue }
                if dist[ny * cols + nx] < best { best = dist[ny * cols + nx]; bx = nx; by = ny }
            }
            if bx == cx, by == cy { break }
            cx = bx; cy = by
        }
        return Vec((Double(cx) + 0.5) * cell, (Double(cy) + 0.5) * cell)
    }
}

final class Checker {
    let hole: Hole
    let field: DistanceField
    let offsets: [Double]
    var sims = 0

    init(_ hole: Hole) {
        self.hole = hole
        field = DistanceField(hole)
        if let w = hole.windmills.first {
            let period = 2 * Double.pi / (abs(w.speed) * Double(w.blades))
            offsets = [0, period / 3, period * 2 / 3]
        } else {
            offsets = [0]
        }
    }

    // MARK: Playing a shot

    func run(from p: Vec, _ shot: Attempt) -> Outcome {
        sims += 1
        var sim = Simulation(hole: hole)
        sim.pos = p
        sim.time = shot.offset
        sim.launch(Vec(cos(shot.angle), sin(shot.angle)) * shot.speed)
        var events: [SimEvent] = []
        var steps = 0
        while sim.isMoving, steps < 2400 {
            events.removeAll(keepingCapacity: true)
            if sim.step(events: &events) {
                for e in events {
                    if case .sank = e { return .sank }
                    if case .hazard = e { return .hazard }
                }
            }
            steps += 1
        }
        return .rest(sim.pos)
    }

    /// The route a shot takes (for drawing).
    func trace(from p: Vec, _ shot: Attempt) -> [Vec] {
        var sim = Simulation(hole: hole)
        sim.pos = p
        sim.time = shot.offset
        sim.launch(Vec(cos(shot.angle), sin(shot.angle)) * shot.speed)
        var events: [SimEvent] = []
        var points = [p]
        var steps = 0
        while sim.isMoving, steps < 2400 {
            events.removeAll(keepingCapacity: true)
            let ended = sim.step(events: &events)
            steps += 1
            if steps % 3 == 0 { points.append(sim.pos) }
            if ended { points.append(sim.pos); break }
        }
        return points
    }

    // MARK: Which shots to try

    func coarseShots() -> [Attempt] {
        var out: [Attempt] = []
        for i in 0..<40 {
            let a = Double(i) / 40 * 2 * .pi
            for v in [170.0, 300, 440, 600, 800, 950] {
                for o in offsets { out.append(Attempt(angle: a, speed: v, offset: o)) }
            }
        }
        return out
    }

    func aimedShots(from p: Vec) -> [Attempt] {
        var out: [Attempt] = []
        let to = hole.cup - p
        let angle = atan2(to.y, to.x)
        let v0 = (2 * Simulation.grass * to.length).squareRoot()
        for da in [-1.5, -0.75, 0, 0.75, 1.5] {
            for k in 0..<24 {
                let v = min(Shot.maxSpeed, v0 * (0.7 + Double(k) * 0.04) + 40)
                for o in offsets { out.append(Attempt(angle: angle + da * .pi / 180, speed: v, offset: o)) }
            }
        }
        // Along the walking route, for corners.
        let wp = field.waypoint(from: p, steps: 14)
        let wv = wp - p
        if wv.length > 20 {
            let wa = atan2(wv.y, wv.x)
            for v in [150.0, 220, 300, 400, 520, 650, 800] {
                for o in offsets { out.append(Attempt(angle: wa, speed: v, offset: o)) }
            }
        }
        return out
    }

    // MARK: Robustness

    /// How much of the neighbourhood of a winning shot still sinks.
    func window(from p: Vec, _ shot: Attempt) -> Double {
        var hits = 0, total = 0
        let times = offsets.count > 1 ? [shot.offset - 0.1, shot.offset, shot.offset + 0.1] : [shot.offset]
        for da in [-2.0, -1.0, 0, 1.0, 2.0] {
            for f in [0.96, 1.0, 1.04] {
                for t in times {
                    total += 1
                    if case .sank = run(from: p, Attempt(angle: shot.angle + da * .pi / 180, speed: shot.speed * f, offset: t)) { hits += 1 }
                }
            }
        }
        return Double(hits) / Double(total)
    }

    /// Whether a sink can still be found from spots a little off the given one (a ball never stops
    /// exactly where a plan says it will).
    func regionCanSink(_ p: Vec) -> Bool {
        var ok = 0
        let around = [Vec(14, 0), Vec(-14, 0), Vec(0, 14), Vec(0, -14)]
        for d in around {
            let q = p + d
            guard Poly.contains(hole.outline, q) else { ok += 1; continue }
            for s in aimedShots(from: q) {
                if case .sank = run(from: q, s) { ok += 1; break }
            }
        }
        return ok >= 3
    }

    // MARK: The search

    func analyze() -> Report {
        var report = Report()

        // From the tee: how punishing is the ground?
        var hazards = 0, total = 0
        for s in coarseShots() {
            total += 1
            if case .hazard = run(from: hole.tee, s) { hazards += 1 }
        }
        report.hazardRate = Double(hazards) / Double(max(1, total))

        var states = [hole.tee]
        var chains: [[(from: Vec, shot: Attempt)]] = [[]]
        var visited = Set<Int>()
        var earlyStates: [Vec] = []
        let maxDepth = 6
        for depth in 1...maxDepth {
            var sinks: [(from: Vec, shot: Attempt, chain: [(from: Vec, shot: Attempt)])] = []
            var next: [(Vec, Double, [(from: Vec, shot: Attempt)])] = []
            for (si, st) in states.enumerated() {
                var shots = aimedShots(from: st)
                if depth <= 2 || next.count < 8 { shots += coarseShots() }
                for shot in shots {
                    switch run(from: st, shot) {
                    case .sank:
                        if sinks.count < 40 { sinks.append((st, shot, chains[si])) }
                    case .hazard:
                        break
                    case .rest(let p):
                        if p.distance(to: st) > 25 {
                            let key = Int(p.x / 22) * 1000 + Int(p.y / 22)
                            if visited.insert(key).inserted { next.append((p, field.at(p), chains[si] + [(st, shot)])) }
                        }
                    }
                }
                if sinks.count >= 40 { break }
            }
            if !sinks.isEmpty {
                // Prefer the most forgiving winning shot.
                var scored = sinks.map { (s: $0, w: window(from: $0.from, $0.shot)) }
                scored.sort { $0.w > $1.w }
                for cand in scored.prefix(6) where cand.w >= 0.2 {
                    if regionCanSink(cand.s.from) || cand.s.from == hole.tee {
                        report.optimal = depth
                        report.window = cand.w
                        report.solution = cand.s.chain + [(cand.s.from, cand.s.shot)]
                        break
                    }
                }
                if report.optimal != nil { break }
            }
            if depth == 1 { earlyStates = next.map { $0.0 } }
            next.sort { $0.1 < $1.1 }
            let kept = Array(next.prefix(26))
            states = kept.map { $0.0 }
            chains = kept.map { $0.2 }
            if states.isEmpty { break }
        }

        // Can the ball get stuck somewhere it started?
        var stuck = 0
        let sample = Array(earlyStates.enumerated().filter { $0.offset % max(1, earlyStates.count / 10) == 0 }.map { $0.element }.prefix(10))
        for st in sample {
            var escaped = false
            for i in 0..<24 where !escaped {
                for v in [200.0, 500] {
                    if case .rest(let p) = run(from: st, Attempt(angle: Double(i) / 24 * 2 * .pi, speed: v, offset: offsets[0])), p.distance(to: st) > 60 {
                        escaped = true
                        break
                    }
                }
            }
            if !escaped { stuck += 1 }
        }
        report.trapRate = sample.isEmpty ? 0 : Double(stuck) / Double(sample.count)
        report.sims = sims
        return report
    }
}

// MARK: - Telling holes apart

/// A coarse picture of a hole: what is on each patch of ground.
struct Fingerprint {
    static let cols = 24, rows = 36
    var cells: [UInt8]

    init(_ h: Hole) {
        let landscape = h.size.x > h.size.y
        let c = landscape ? Self.rows : Self.cols, r = landscape ? Self.cols : Self.rows
        var grid = [UInt8](repeating: 0, count: c * r)
        for y in 0..<r {
            for x in 0..<c {
                let p = Vec((Double(x) + 0.5) * h.size.x / Double(c), (Double(y) + 0.5) * h.size.y / Double(r))
                var v: UInt8 = 0
                if Poly.contains(h.outline, p) {
                    v = 1
                    for patch in h.patches where patch.contains(p) {
                        switch patch.kind {
                        case .sand, .mud: v = 3
                        case .ice: v = 4
                        case .water: v = 5
                        case .lava: v = 6
                        case .slope, .wind: v = 7
                        }
                    }
                    for b in h.blocks where Poly.contains(b, p) { v = 2 }
                }
                for b in h.bumpers where b.center.distance(to: p) < b.radius + 8 { v = 8 }
                for w in h.windmills where w.center.distance(to: p) < w.length { v = 8 }
                for m in h.magnets where m.center.distance(to: p) < 30 { v = 8 }
                grid[y * c + x] = v
            }
        }
        if landscape {
            var t = [UInt8](repeating: 0, count: Self.cols * Self.rows)
            for y in 0..<r { for x in 0..<c { t[x * Self.cols + y] = grid[y * c + x] } }
            cells = t
        } else {
            cells = grid
        }
    }

    private func flipped(x: Bool, y: Bool) -> [UInt8] {
        var out = cells
        for j in 0..<Self.rows {
            for i in 0..<Self.cols {
                let sx = x ? Self.cols - 1 - i : i, sy = y ? Self.rows - 1 - j : j
                out[j * Self.cols + i] = cells[sy * Self.cols + sx]
            }
        }
        return out
    }

    /// How alike two holes look, trying each mirror image: (shape, features), each 0...1.
    func similarity(to other: Fingerprint) -> (shape: Double, features: Double) {
        var best = (shape: 0.0, features: 0.0)
        for (fx, fy) in [(false, false), (true, false), (false, true), (true, true)] {
            let o = other.flipped(x: fx, y: fy)
            var interS = 0, unionS = 0, interF = 0, unionF = 0
            for i in 0..<cells.count {
                let a = cells[i], b = o[i]
                if a != 0 || b != 0 { unionS += 1; if a != 0, b != 0 { interS += 1 } }
                if a >= 2 || b >= 2 { unionF += 1; if a == b { interF += 1 } }
            }
            let shape = unionS == 0 ? 0 : Double(interS) / Double(unionS)
            let feat = unionF == 0 ? 1 : Double(interF) / Double(unionF)
            if shape > best.shape { best = (shape, feat) }
        }
        return best
    }
}
