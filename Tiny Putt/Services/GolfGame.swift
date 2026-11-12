//
//  GolfGame.swift
//  Tiny Putt
//

import Foundation
import Observation
import SwiftUI

/// Maps the hole's world onto the screen. The whole hole is always visible: it is scaled to fit,
/// and turned a quarter turn when that makes it bigger (a tall hole in a wide window).
struct ViewTransform {
    let scale: CGFloat
    let offset: CGPoint
    let rotated: Bool
    let world: CGSize

    init(world: Vec, view: CGSize) {
        let w = CGFloat(world.x), h = CGFloat(world.y)
        self.world = CGSize(width: w, height: h)
        let upright = max(0.001, min(view.width / w, view.height / h))
        let turned = max(0.001, min(view.width / h, view.height / w))
        rotated = turned > upright * 1.1
        scale = rotated ? turned : upright
        let cw = (rotated ? h : w) * scale
        let ch = (rotated ? w : h) * scale
        offset = CGPoint(x: (view.width - cw) / 2, y: (view.height - ch) / 2)
    }

    var affine: CGAffineTransform {
        rotated
            ? CGAffineTransform(a: 0, b: scale, c: -scale, d: 0, tx: world.height * scale + offset.x, ty: offset.y)
            : CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.x, ty: offset.y)
    }

    func toWorld(_ p: CGPoint) -> Vec {
        let u = Double((p.x - offset.x) / scale), v = Double((p.y - offset.y) / scale)
        return rotated ? Vec(v, Double(world.height) - u) : Vec(u, v)
    }

    /// The part of the world that shows on a screen of this size (more than the hole itself).
    func visibleWorldRect(for view: CGSize) -> CGRect {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: view.width, y: 0), CGPoint(x: 0, y: view.height), CGPoint(x: view.width, y: view.height)]
        let pts = corners.map { toWorld($0) }
        let b = Poly.bounds(pts)
        return CGRect(x: b.lo.x, y: b.lo.y, width: b.hi.x - b.lo.x, height: b.hi.y - b.lo.y)
    }
}

/// A rough idea of where a shot will end up (never exact: that would be boring).
struct LandingEstimate {
    var center: Vec
    var radius: Double
}

/// The whole game: the hole, the ball, the shot being aimed, and who is playing.
@MainActor
@Observable
final class GolfGame {
    enum Phase: Equatable { case aiming, rolling, sinking, hazard, holed }
    enum Overlay: Equatable { case none, campaignDone, versusTurnDone, versusHoleDone }

    /// A head-to-head game on the same holes. Players take turns in a fixed order: each plays
    /// the hole until the ball is in, then the next one goes.
    struct Versus {
        var order: [UUID]
        var turn = 0
        var level: Int
        var holeStrokes: [UUID: Int] = [:]
        var totals: [UUID: Int] = [:]
        var holesPlayed = 0
        var currentID: UUID { order[turn] }
        var isLastTurn: Bool { turn == order.count - 1 }
    }

    // MARK: Observed (the menus and buttons show these)
    private(set) var level = 1
    private(set) var strokes = 0
    private(set) var phase: Phase = .aiming
    private(set) var overlay: Overlay = .none
    private(set) var versus: Versus?
    private(set) var aimPull: Vec?
    private(set) var estimate: LandingEstimate?

    var isSoundOn: Bool {
        didSet { defaults.set(isSoundOn, forKey: Keys.sound); sounds.isEnabled = isSoundOn }
    }
    var isHapticsOn: Bool {
        didSet { defaults.set(isHapticsOn, forKey: Keys.haptics); haptics.isEnabled = isHapticsOn }
    }

    // MARK: Simulation state (redrawn every frame by the canvas, so not observed)
    @ObservationIgnored private(set) var hole: Hole
    @ObservationIgnored private(set) var sim: Simulation
    @ObservationIgnored private(set) var animTime = 0.0
    @ObservationIgnored private(set) var phaseTime = 0.0
    @ObservationIgnored private(set) var popTime = 1.0
    @ObservationIgnored private(set) var bumperPulse: [Double] = []
    @ObservationIgnored private(set) var hazardKind: Hazard = .water
    @ObservationIgnored private(set) var hazardAt = Vec.zero
    @ObservationIgnored private var lastRest = Vec.zero
    @ObservationIgnored private var lastTick: Double?
    @ObservationIgnored private var lastBounceSound = 0.0
    @ObservationIgnored private var sceneryCache: (key: String, items: [SceneryItem])?

    @ObservationIgnored private let sounds = SoundEngine()
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private let defaults = UserDefaults.standard
    let roster = PlayerRoster()

    private enum Keys {
        static let sound = "soundOn"
        static let haptics = "hapticsOn"
    }

    init() {
        let first = HoleLibrary.hole(forLevel: 1)
        hole = first
        sim = Simulation(hole: first)
        isSoundOn = defaults.object(forKey: Keys.sound) as? Bool ?? true
        isHapticsOn = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        sounds.isEnabled = isSoundOn
        haptics.isEnabled = isHapticsOn
        load(level: roster.current.level)
    }

    // MARK: - Who is playing

    var playerID: UUID { versus?.currentID ?? roster.current.id }
    var ballColor: BallColor { roster.player(playerID)?.ball ?? .white }
    var playerName: String { roster.player(playerID)?.name ?? "" }
    var isVersus: Bool { versus != nil }
    var isIdle: Bool { phase == .aiming && aimPull == nil && popTime >= 1 }

    // MARK: - Starting and leaving

    /// Plays the level the current player is up to.
    func startCampaign() {
        versus = nil
        load(level: roster.current.level)
    }

    /// Players take turns on the same holes, starting from the first player's level.
    func startVersus(order: [UUID]) {
        guard order.count >= 2, let start = roster.player(order[0])?.level else { return }
        versus = Versus(order: order, level: start)
        load(level: start)
    }

    func leave() {
        versus = nil
        aimPull = nil
        estimate = nil
        lastTick = nil
        load(level: roster.current.level)
    }

    private func load(level n: Int) {
        level = n
        hole = HoleLibrary.hole(forLevel: n)
        sim = Simulation(hole: hole)
        lastRest = hole.tee
        strokes = 0
        phase = .aiming
        overlay = .none
        aimPull = nil
        estimate = nil
        phaseTime = 0
        popTime = 0
        bumperPulse = Array(repeating: 0, count: hole.bumpers.count)
        sceneryCache = nil
    }

    #if DEBUG
    /// Debug: jumps to another hole without playing.
    func debugSkip(by delta: Int) { load(level: max(1, level + delta)) }
    #endif

    func replayHole() {
        load(level: level)
    }

    /// After a finished hole: the next level (or, in versus, the next player or hole).
    func next() {
        if var v = versus {
            if overlay == .versusTurnDone {
                v.turn += 1
            } else {
                v.turn = 0
                v.level += 1
                v.holeStrokes = [:]
            }
            versus = v
            load(level: v.level)
        } else {
            load(level: roster.current.level)
        }
    }

    // MARK: - Aiming

    func updateAim(start: CGPoint, current: CGPoint, size: CGSize) {
        guard phase == .aiming, overlay == .none, popTime >= 0.6 else { return }
        if aimPull == nil { sounds.prepare() }
        let t = ViewTransform(world: hole.size, view: size)
        let pull = t.toWorld(start) - t.toWorld(current)
        let length = pull.length
        guard length >= Shot.minPull else {
            aimPull = nil
            estimate = nil
            return
        }
        let clamped = pull * min(1, Shot.maxPull / length)
        aimPull = clamped
        estimate = makeEstimate(for: clamped)
    }

    func cancelAim() {
        aimPull = nil
        estimate = nil
    }

    /// Lets go of the drag: hits the ball if the pull was long enough.
    func releaseAim() {
        guard phase == .aiming, let pull = aimPull else { cancelAim(); return }
        let length = pull.length
        let power = Shot.power(forPull: length)
        sim.launch(pull.normalized * Shot.speed(forPull: length))
        strokes += 1
        phase = .rolling
        phaseTime = 0
        cancelAim()
        sounds.play(.hit(power: power))
        haptics.hit(power: power)
    }

    /// A deliberately blurry guess: the real result, nudged and shown as a soft circle.
    private func makeEstimate(for pull: Vec) -> LandingEstimate {
        var probe = sim
        probe.launch(pull.normalized * Shot.speed(forPull: pull.length))
        var events: [SimEvent] = []
        var steps = 0
        while probe.isMoving, steps < 240 * 12 {
            if probe.step(events: &events) { break }
            events.removeAll(keepingCapacity: true)
            steps += 1
        }
        let travelled = probe.pos.distance(to: sim.pos)
        let radius = 16 + travelled * 0.12
        let nudge = Vec(sin(pull.x * 0.31 + pull.y * 0.17), cos(pull.x * 0.13 - pull.y * 0.29)) * (radius * 0.45)
        return LandingEstimate(center: probe.pos + nudge, radius: radius)
    }

    // MARK: - Frame update

    /// Whether anything is moving and the canvas must draw at the full frame rate.
    var isBusy: Bool { phase != .aiming || aimPull != nil || popTime < 1 }

    func advance(to date: Date) {
        let now = date.timeIntervalSinceReferenceDate
        defer { lastTick = now }
        guard let last = lastTick else { return }
        let dt = min(now - last, 1.0 / 15.0)
        guard dt > 0 else { return }
        animTime += dt
        phaseTime += dt
        if popTime < 1 { popTime = min(1, popTime + dt / 0.35) }
        for i in bumperPulse.indices where bumperPulse[i] > 0 { bumperPulse[i] = max(0, bumperPulse[i] - dt * 5) }

        switch phase {
        case .aiming, .holed:
            sim.time += dt
        case .rolling:
            var events: [SimEvent] = []
            let ended = sim.advance(by: dt, events: &events)
            handle(events)
            if !ended, phase == .rolling, !sim.isMoving {
                lastRest = sim.pos
                phase = .aiming
            }
        case .sinking:
            sim.time += dt
            if phaseTime >= 0.5 { finishHole() }
        case .hazard:
            sim.time += dt
            if phaseTime >= 1.0 {
                sim.pos = lastRest
                sim.vel = .zero
                popTime = 0
                phase = .aiming
            }
        }
    }

    private func handle(_ events: [SimEvent]) {
        for event in events {
            switch event {
            case .wall(let speed):
                let strength = min(1, speed / 500)
                // Don't machine-gun the same sound while the ball scrapes along a wall.
                if animTime - lastBounceSound > 0.05, strength > 0.08 {
                    lastBounceSound = animTime
                    sounds.play(.bounce(impact: strength))
                    haptics.bounce(strength: strength)
                }
            case .windmill(let speed):
                if animTime - lastBounceSound > 0.05 {
                    lastBounceSound = animTime
                    sounds.play(.bounce(impact: min(1, speed / 500)))
                }
            case .bumper(let index):
                if bumperPulse.indices.contains(index) { bumperPulse[index] = 1 }
                sounds.play(.bumper)
                haptics.bumper()
            case .sank:
                phase = .sinking
                phaseTime = 0
                sounds.play(.cup)
                haptics.success()
            case .hazard(let kind):
                strokes += 1
                hazardKind = kind
                hazardAt = sim.pos
                sim.vel = .zero
                phase = .hazard
                phaseTime = 0
                switch kind {
                case .water: sounds.play(.splash)
                case .lava: sounds.play(.lava)
                case .outOfBounds: sounds.play(.splash)
                }
                haptics.hazard()
            }
        }
    }

    private func finishHole() {
        phase = .holed
        if var v = versus {
            v.holeStrokes[v.currentID] = strokes
            v.totals[v.currentID, default: 0] += strokes
            if v.isLastTurn {
                v.holesPlayed += 1
                overlay = .versusHoleDone
            } else {
                overlay = .versusTurnDone
            }
            versus = v
        } else {
            roster.finish(level: level, strokes: strokes, for: roster.current.id)
            overlay = .campaignDone
        }
    }

    // MARK: - Drawing helpers

    /// How the ball is drawn right now: where, and how big (it pops in at the tee, shrinks into
    /// the cup, and sinks into water).
    var displayBall: (pos: Vec, scale: Double)? {
        switch phase {
        case .sinking:
            let t = min(1, phaseTime / 0.4)
            return (sim.pos, 1 - t * 0.9)
        case .hazard:
            let t = min(1, phaseTime / 0.35)
            return t >= 1 ? nil : (hazardAt, 1 - t)
        case .holed:
            return nil
        default:
            guard popTime < 1 else { return (sim.pos, 1) }
            let u = popTime - 1
            let c1 = 2.2
            return (sim.pos, max(0, 1 + (c1 + 1) * u * u * u + c1 * u * u))
        }
    }

    func scenery(for rect: CGRect) -> [SceneryItem] {
        let key = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        if let cache = sceneryCache, cache.key == key { return cache.items }
        let items = Scenery.make(in: rect, avoiding: hole.outline, theme: hole.theme)
        sceneryCache = (key, items)
        return items
    }

    // MARK: - Results

    var scoreTitle: String { Self.title(strokes: strokes, par: hole.par) }

    static func title(strokes: Int, par: Int) -> String {
        if strokes == 1 { return "Hole in one!" }
        switch strokes - par {
        case ...(-2): return "Eagle!"
        case -1: return "Birdie!"
        case 0: return "Par"
        case 1: return "Bogey"
        default: return "+\(strokes - par)"
        }
    }

    func resetEverything() {
        roster.resetAll()
        versus = nil
        load(level: 1)
    }
}
