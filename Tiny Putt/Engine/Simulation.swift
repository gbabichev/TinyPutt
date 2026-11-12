//
//  Simulation.swift
//  Tiny Putt
//
//  The ball physics. Deterministic and fixed-step, so the game, the aiming estimate and the
//  hole checker all agree on what a shot does.
//

import Foundation

/// How a pull on the screen becomes a shot.
nonisolated enum Shot {
    /// The longest pull, in world units. Measured in the world (not on screen), so a shot feels
    /// the same on every screen size.
    static let maxPull: Double = 170
    static let minPull: Double = 14
    static let minSpeed: Double = 150
    static let maxSpeed: Double = 950

    /// 0...1
    static func power(forPull length: Double) -> Double {
        max(0, min(1, (length - minPull) / (maxPull - minPull)))
    }

    static func speed(forPull length: Double) -> Double {
        minSpeed + (maxSpeed - minSpeed) * pow(power(forPull: length), 1.25)
    }
}

nonisolated enum Hazard: Sendable {
    case water, lava, outOfBounds
}

nonisolated enum SimEvent: Sendable {
    case wall(speed: Double)
    case bumper(index: Int)
    case windmill(speed: Double)
    case sank
    case hazard(Hazard)
}

nonisolated struct Simulation: Sendable {
    static let ballRadius = 7.0
    static let cupRadius = 11.0
    static let dt = 1.0 / 240.0

    // Rolling resistance (speed lost per second) on each surface.
    static let grass = 300.0
    static let sand = 850.0
    static let mud = 1500.0
    static let ice = 35.0
    /// How much stronger a slope belt pushes than its listed strength. Grass friction is 300, so
    /// a belt has to be well past that to feel like a conveyor.
    static let beltBoost = 2.3

    let hole: Hole
    var pos: Vec
    var vel: Vec = .zero
    /// Time since the hole began. Windmills turn with it, so it keeps running between shots.
    var time = 0.0
    var shotTime = 0.0
    private var accumulator = 0.0
    private var stepCount = 0

    var isMoving: Bool { vel != .zero }

    init(hole: Hole) {
        self.hole = hole
        pos = hole.tee
    }

    mutating func launch(_ velocity: Vec) {
        vel = velocity
        shotTime = 0
    }

    /// Runs the simulation for `elapsed` seconds in fixed steps. Returns true if the shot ended
    /// (in the cup or in a hazard), and the events are in `events`.
    mutating func advance(by elapsed: Double, events: inout [SimEvent]) -> Bool {
        accumulator += elapsed
        while accumulator >= Self.dt {
            accumulator -= Self.dt
            if step(events: &events) { return true }
            if !isMoving { accumulator = 0; return false }
        }
        return false
    }

    /// One fixed step. Returns true when the shot is over because of the cup or a hazard.
    mutating func step(events: inout [SimEvent]) -> Bool {
        let dt = Self.dt
        time += dt
        shotTime += dt
        let r = Self.ballRadius

        // What the ball is rolling on.
        var friction = Self.grass
        var accel = Vec.zero
        for patch in hole.patches where patch.contains(pos) {
            switch patch.kind {
            case .sand: friction = Self.sand
            case .mud: friction = Self.mud
            case .ice: friction = Self.ice
            case .slope(let a): accel += a * Self.beltBoost
            case .wind(let a): accel += a
            case .water:
                events.append(.hazard(.water)); return true
            case .lava:
                events.append(.hazard(.lava)); return true
            }
        }
        for m in hole.magnets {
            let d = m.center - pos
            let dist = d.length
            if dist < m.radius, dist > 1 { accel += d / dist * (m.strength * (1 - dist / m.radius)) }
        }
        for b in hole.bowls {
            let d = b.center - pos
            let dist = d.length
            if dist < b.radius, dist > 1 { accel += d / dist * (b.strength * dist / b.radius) }
        }
        // A shot that goes on too long is slowed so it always ends.
        if shotTime > 14 { friction *= 6 }

        vel += accel * dt
        let speed = vel.length
        if speed > 0 {
            let next = max(0, speed - friction * dt)
            vel = vel * (next / speed)
            if next < 5, accel.length <= friction { vel = .zero }
        }
        pos += vel * dt

        // Walls: only the segments listed for the cell the ball is in.
        let cx = Int((pos.x - hole.gridOrigin.x) / Hole.cellSize)
        let cy = Int((pos.y - hole.gridOrigin.y) / Hole.cellSize)
        if cx >= 0, cx < hole.gridCols, cy >= 0, cy < hole.gridRows {
            let cell = cy * hole.gridCols + cx
            var k = Int(hole.cellStart[cell])
            let end = Int(hole.cellStart[cell + 1])
            while k < end {
                let s = hole.segments[Int(hole.cellSegments[k])]
                k += 1
                let c = Poly.closestPoint(s.a, s.b, to: pos)
                let d = pos - c
                let dist = d.length
                if dist < r {
                    let n = dist > 1e-9 ? d / dist : (s.b - s.a).normalized.perp
                    pos += n * (r - dist)
                    let vn = vel.dot(n)
                    if vn < 0 {
                        vel -= n * (vn * 1.75)
                        events.append(.wall(speed: -vn))
                    }
                }
            }
        }

        // Bumpers throw the ball back harder than it came.
        for (i, b) in hole.bumpers.enumerated() {
            let d = pos - b.center
            let dist = d.length
            if dist < b.radius + r {
                let n = dist > 1e-9 ? d / dist : Vec(0, -1)
                pos = b.center + n * (b.radius + r)
                if vel.dot(n) < 0 {
                    vel -= n * (vel.dot(n) * 2)
                    let out = min(Shot.maxSpeed, max(vel.length * 0.92 + 120, 340))
                    vel = vel.normalized * out
                    events.append(.bumper(index: i))
                }
            }
        }

        collideWindmills(events: &events)

        // The cup takes a ball that is slow enough.
        let toCup = hole.cup - pos
        let cupDist = toCup.length
        if cupDist < Self.cupRadius * 0.9, vel.length < 430 {
            pos = hole.cup
            vel = .zero
            events.append(.sank)
            return true
        }

        // Safety net: never lose the ball outside the course (checked every few steps).
        stepCount &+= 1
        if stepCount % 6 == 0, !Poly.contains(hole.outline, pos) {
            events.append(.hazard(.outOfBounds))
            return true
        }
        return false
    }

    /// Windmills: a hub, and blades that carry the ball along when they hit it.
    private mutating func collideWindmills(events: inout [SimEvent]) {
        let r = Self.ballRadius
        for w in hole.windmills {
            let hubD = pos - w.center
            let hubDist = hubD.length
            if hubDist < w.hub + r {
                let n = hubDist > 1e-9 ? hubD / hubDist : Vec(0, -1)
                pos = w.center + n * (w.hub + r)
                if vel.dot(n) < 0 {
                    vel -= n * (vel.dot(n) * 1.6)
                    events.append(.windmill(speed: vel.length))
                }
            }
            for k in 0..<w.blades {
                let tip = w.tip(of: k, at: time)
                let c = Poly.closestPoint(w.center, tip, to: pos)
                let d = pos - c
                let dist = d.length
                let reach = w.thickness / 2 + r
                if dist < reach {
                    let n = dist > 1e-9 ? d / dist : (tip - w.center).normalized.perp
                    pos += n * (reach - dist)
                    let surface = (c - w.center).perp * w.speed
                    var rel = vel - surface
                    let rn = rel.dot(n)
                    if rn < 0 {
                        rel -= n * (rn * 1.6)
                        vel = rel + surface
                        events.append(.windmill(speed: -rn))
                    }
                }
            }
        }
    }

    /// A step while the ball sits still: time moves on, and a windmill blade that sweeps into the
    /// ball knocks it (so a blade never passes through a resting ball).
    mutating func restStep(events: inout [SimEvent]) {
        time += Self.dt
        collideWindmills(events: &events)
    }
}
