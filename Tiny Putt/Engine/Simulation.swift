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
    static let minSpeed: Double = 120
    static let maxSpeed: Double = 950

    /// 0...1
    static func power(forPull length: Double) -> Double {
        max(0, min(1, (length - minPull) / (maxPull - minPull)))
    }

    static func speed(forPull length: Double) -> Double {
        minSpeed + (maxSpeed - minSpeed) * power(forPull: length)
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
    /// A ball went through a portal (`tunnel` when it went by pipe).
    case portal(tunnel: Bool)
    case boost
    case switchPressed
    case broke
    case pad
    case launch
    case land
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
    /// The outer share of a dish or hill over which its pull eases in from nothing.
    static let bowlRim = 0.3
    /// Where the ball was (relative to the cup) and how fast it was going when the cup took it.
    var sankOffset = Vec.zero
    var sankVel = Vec.zero
    /// The kick a speed pad gives, and how a ramp turns speed into flight time (seconds = speed / this).
    static let boostKick = 330.0
    static let flightDivisor = 1600.0

    let hole: Hole
    var pos: Vec
    var vel: Vec = .zero
    /// Time since the hole began. Windmills turn with it, so it keeps running between shots.
    var time = 0.0
    var shotTime = 0.0
    private var accumulator = 0.0
    private var stepCount = 0

    // State that carries from one stroke to the next (doors stay open, bricks stay broken).
    /// A bit for each door that a switch has opened.
    var doorsOpen: UInt32 = 0
    /// A bit for each breakable block that has been smashed.
    var broken: UInt32 = 0

    // State within a stroke.
    /// Seconds of flight left (after a ramp), and how long the flight is in all.
    private(set) var airTime = 0.0
    private(set) var airTotal = 0.0
    /// Seconds left inside a tunnel; the ball's speed is kept for when it comes out.
    private(set) var holdTime = 0.0
    private var heldVel = Vec.zero
    /// The end of a portal the ball just came out of (it cannot go straight back in).
    private var portalLock = -1
    private var onBoost = false
    private var onRamp = false

    var isMoving: Bool { vel != .zero || holdTime > 0 }
    var isFlying: Bool { airTime > 0 }
    /// 0...1 through the current flight.
    var airProgress: Double { airTotal > 0 ? 1 - airTime / airTotal : 0 }

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

        // Inside a tunnel the ball is out of play until it comes out the other end.
        if holdTime > 0 {
            holdTime -= dt
            if holdTime <= 0 { holdTime = 0; vel = heldVel; heldVel = .zero }
            return false
        }

        let flying = airTime > 0
        if flying {
            airTime = max(0, airTime - dt)
            if airTime == 0 { events.append(.land) }
        }

        // What the ball is rolling on (a ball in the air touches none of it).
        var friction = flying ? 0 : Self.grass
        var accel = Vec.zero
        if !flying {
            var bridged = false
            for patch in hole.patches {
                if case .bridge = patch.kind, patch.contains(pos) { bridged = true; break }
            }
            var boosting = false, ramping = false
            for patch in hole.patches where patch.contains(pos) {
                switch patch.kind {
                case .sand: friction = Self.sand
                case .mud: friction = Self.mud
                case .ice: friction = Self.ice
                case .slope(let a): accel += a * Self.beltBoost
                case .wind(let a): accel += a
                case .water:
                    if !bridged { events.append(.hazard(.water)); return true }
                case .lava:
                    if !bridged { events.append(.hazard(.lava)); return true }
                case .bridge: break
                case .boost(let dir):
                    boosting = true
                    if !onBoost {
                        vel = vel + dir.normalized * Self.boostKick
                        if vel.length > Shot.maxSpeed { vel = vel.normalized * Shot.maxSpeed }
                        events.append(.boost)
                    }
                case .ramp(let dir):
                    ramping = true
                    let speed = vel.length
                    if !onRamp, speed > 140, vel.dot(dir.normalized) > 0.3 * speed {
                        airTotal = max(0.12, min(0.5, speed / Self.flightDivisor))
                        airTime = airTotal
                        events.append(.launch)
                    }
                }
            }
            onBoost = boosting
            onRamp = ramping
            for m in hole.magnets {
                let d = m.center - pos
                let dist = d.length
                if dist < m.radius, dist > 1 { accel += d / dist * (m.strength * (1 - dist / m.radius)) }
            }
            for b in hole.bowls {
                let d = b.center - pos
                let dist = d.length
                if dist < b.radius, dist > 1 {
                    // Linear toward the centre, but eased in over the outer rim so a ball that only
                    // just crosses the edge is not yanked down the slope.
                    let u = dist / b.radius
                    let ease = min(1, (1 - u) / Self.bowlRim)
                    accel += d / dist * (b.strength * u * ease * ease * (3 - 2 * ease))
                }
            }
        }
        // A shot that goes on too long is slowed so it always ends.
        if shotTime > 14 { friction *= 6 }

        vel += accel * dt
        let speed = vel.length
        if speed > 0 {
            let next = max(0, speed - friction * dt)
            vel = vel * (next / speed)
            if next < 5, accel.length <= friction, !flying { vel = .zero }
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
                _ = bounceOff(s.a, s.b, events: &events)
            }
        }

        // Doors that are still shut are walls too.
        for (i, door) in hole.doors.enumerated() where doorsOpen & (1 << UInt32(i)) == 0 {
            for j in 0..<door.outline.count {
                _ = bounceOff(door.outline[j], door.outline[(j + 1) % door.outline.count], events: &events)
            }
        }

        // Breakable blocks: a hard hit smashes them, a soft one just bounces.
        for (i, block) in hole.breakables.enumerated() where broken & (1 << UInt32(i)) == 0 {
            for j in 0..<block.outline.count {
                let a = block.outline[j], b = block.outline[(j + 1) % block.outline.count]
                let c = Poly.closestPoint(a, b, to: pos)
                let d = pos - c
                let dist = d.length
                guard dist < r else { continue }
                let n = dist > 1e-9 ? d / dist : (b - a).normalized.perp
                let vn = vel.dot(n)
                if vn < 0, -vn >= block.breakSpeed {
                    broken |= 1 << UInt32(i)
                    vel = vel * 0.8
                    events.append(.broke)
                    break
                }
                pos += n * (r - dist)
                if vn < 0 {
                    vel -= n * (vn * 1.75)
                    events.append(.wall(speed: -vn))
                }
            }
        }

        // A ball in the air passes over everything below, and the things that stand in the way.
        if !flying {
            // One-way gates.
            for g in hole.oneWays {
                let c = Poly.closestPoint(g.a, g.b, to: pos)
                let d = pos - c
                let dist = d.length
                guard dist < r, d.dot(g.front) > 0 else { continue }
                let n = dist > 1e-9 ? d / dist : g.front
                pos += n * (r - dist)
                let vn = vel.dot(n)
                if vn < 0 {
                    vel -= n * (vn * 1.75)
                    events.append(.wall(speed: -vn))
                }
            }

            // Springy bars.
            for bar in hole.bouncePads {
                let c = Poly.closestPoint(bar.a, bar.b, to: pos)
                let d = pos - c
                let dist = d.length
                let reach = r + 4
                guard dist < reach else { continue }
                let n = dist > 1e-9 ? d / dist : (bar.b - bar.a).normalized.perp
                pos += n * (reach - dist)
                let vn = vel.dot(n)
                if vn < 0 {
                    let tangent = vel - n * vn
                    vel = tangent + n * min(Shot.maxSpeed, max(380, -vn * 1.25))
                    events.append(.pad)
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

            collideTimed(events: &events)

            // Floor switches open their doors.
            for (i, b) in hole.switches.enumerated() where doorsOpen & (1 << UInt32(i)) == 0 {
                if pos.distance(to: b.center) < b.radius {
                    doorsOpen |= 1 << UInt32(i)
                    events.append(.switchPressed)
                }
            }

            // Portals and tunnels.
            if portalLock >= 0 {
                let p = hole.portals[portalLock / 2]
                let exit = portalLock % 2 == 0 ? p.a : p.b
                if pos.distance(to: exit) > p.radius * 1.6 { portalLock = -1 }
            }
            if portalLock < 0 {
                search: for (i, p) in hole.portals.enumerated() {
                    for side in 0..<2 {
                        let from = side == 0 ? p.a : p.b
                        let to = side == 0 ? p.b : p.a
                        if pos.distance(to: from) < p.radius * 0.8 {
                            pos = to
                            portalLock = i * 2 + (1 - side)
                            if p.delay > 0 { heldVel = vel; vel = .zero; holdTime = p.delay }
                            events.append(.portal(tunnel: p.isTunnel))
                            break search
                        }
                    }
                }
            }

            // The cup takes a ball that is slow enough.
            let toCup = hole.cup - pos
            let cupDist = toCup.length
            if cupDist < Self.cupRadius * 0.9, vel.length < 430 {
                sankOffset = pos - hole.cup
                sankVel = vel
                pos = hole.cup
                vel = .zero
                events.append(.sank)
                return true
            }
        }

        // Safety net: never lose the ball outside the course (checked every few steps).
        stepCount &+= 1
        if stepCount % 6 == 0, !Poly.contains(hole.outline, pos) {
            events.append(.hazard(.outOfBounds))
            return true
        }
        return false
    }

    /// Pushes the ball out of a plain wall and bounces it. Returns true if it touched.
    private mutating func bounceOff(_ a: Vec, _ b: Vec, events: inout [SimEvent]) -> Bool {
        let c = Poly.closestPoint(a, b, to: pos)
        let d = pos - c
        let dist = d.length
        guard dist < Self.ballRadius else { return false }
        let n = dist > 1e-9 ? d / dist : (b - a).normalized.perp
        pos += n * (Self.ballRadius - dist)
        let vn = vel.dot(n)
        if vn < 0 {
            vel -= n * (vn * 1.75)
            events.append(.wall(speed: -vn))
        }
        return true
    }

    /// Windmills: a hub, and blades that carry the ball along when they hit it.
    private mutating func collideTimed(events: inout [SimEvent]) {
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

        // Walls that slide or swing.
        let dt = Self.dt
        for m in hole.movers {
            let now = m.ends(at: time), soon = m.ends(at: time + dt)
            let ab = now.b - now.a
            let len2 = max(ab.dot(ab), 1e-9)
            let t = max(0, min(1, (pos - now.a).dot(ab) / len2))
            let c = now.a + ab * t
            let d = pos - c
            let dist = d.length
            let reach = m.thickness / 2 + r
            guard dist < reach else { continue }
            let n = dist > 1e-9 ? d / dist : ab.normalized.perp
            pos += n * (reach - dist)
            let surface = ((soon.a + (soon.b - soon.a) * t) - c) / dt
            var rel = vel - surface
            let rn = rel.dot(n)
            if rn < 0 {
                rel -= n * (rn * 1.6)
                vel = rel + surface
                events.append(.windmill(speed: -rn))
            }
        }
    }

    /// A step while the ball sits still: time moves on, and a windmill blade or a moving wall that
    /// sweeps into the ball knocks it (so nothing ever passes through a resting ball).
    mutating func restStep(events: inout [SimEvent]) {
        time += Self.dt
        collideTimed(events: &events)
    }
}
