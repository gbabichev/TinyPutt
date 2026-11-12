//
//  main.swift
//  HoleChecker
//
//  Builds the campaign: for each level it tries seeds until the generator makes a hole that is
//  finishable, forgiving, trap-free and unlike the holes before it, then writes the accepted
//  seeds to CampaignTable.swift.
//
//  Build and run (from the repository root):
//    swiftc -swift-version 5 -O -o /tmp/holechecker Tools/HoleChecker/*.swift \
//      "Tiny Putt/Engine/Geometry.swift" "Tiny Putt/Engine/Hole.swift" "Tiny Putt/Engine/Simulation.swift" \
//      "Tiny Putt/Engine/HoleGenerator.swift" "Tiny Putt/Engine/HoleLibrary.swift" "Tiny Putt/Engine/CampaignTable.swift" "Tiny Putt/Engine/DifficultySamples.swift"
//    /tmp/holechecker --from 11 --to 50 --out "Tiny Putt/Engine/CampaignTable.swift"
//

import Foundation

struct Options {
    var from = 11, to = 50
    var out: String?
    var attempts = 400
    var sheet: String?
    var solve: Int?
    var levels: [Int]?
    var samples: String?
}

func parse() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--from": o.from = Int(it.next() ?? "") ?? o.from
        case "--to": o.to = Int(it.next() ?? "") ?? o.to
        case "--out": o.out = it.next()
        case "--sheet": o.sheet = it.next()
        case "--solve": o.solve = Int(it.next() ?? "")
        case "--levels": o.levels = (it.next() ?? "").split(separator: ",").compactMap { Int($0) }
        case "--samples": o.samples = it.next()
        case "--attempts": o.attempts = Int(it.next() ?? "") ?? o.attempts
        default: break
        }
    }
    return o
}

struct Accepted {
    var level: Int
    var seed: UInt64
    var theme: ThemeID
    var par: Int
    var gen: Generated
    var fingerprint: Fingerprint
    var report: Report
    var forcedMiddle: Middle?
}

struct Evaluation {
    var seed: UInt64
    var forcedMiddle: Middle?
    var template: Template = .straight
    var gen: Generated
    var fingerprint: Fingerprint
    var report: Report?
}

let options = parse()

// --solve N: show how level N can be beaten (draws the winning shots on the hole).
if let level = options.solve {
    let hole = HoleLibrary.hole(forLevel: level)
    let checker = Checker(hole)
    let report = checker.analyze()
    print("Level \(level): optimal \(report.optimal.map(String.init) ?? "none"), window \(report.window)")
    var routes: [[Vec]] = []
    for (i, step) in report.solution.enumerated() {
        let degrees = step.shot.angle * 180 / .pi
        print(String(format: "  stroke %d: from (%.0f, %.0f) angle %.0f° speed %.0f (pull %.0f%% of max) window offset %.2f",
                     i + 1, step.from.x, step.from.y, degrees, step.shot.speed,
                     100 * max(0, (step.shot.speed - Shot.minSpeed) / (Shot.maxSpeed - Shot.minSpeed)), step.shot.offset))
        routes.append(checker.trace(from: step.from, step.shot))
    }
    if let sheet = options.sheet { writeSheet([hole], to: sheet, columns: 1, cell: 900, paths: routes) }
    exit(0)
}
var accepted: [Accepted] = []
var seen: [Fingerprint] = HoleLibrary.handMade.map { Fingerprint($0) }
var templateUse: [Template: Int] = [:]
var middleUse: [Middle: Int] = [:]
let templateCap = max(6, (options.levels?.count ?? (options.to - options.from + 1)) / 4)
let middleCap = max(8, (options.levels?.count ?? (options.to - options.from + 1)) / 3)

func isTooSimilar(_ f: Fingerprint) -> Bool {
    for other in seen {
        let s = f.similarity(to: other)
        if s.shape >= 0.88, s.features >= 0.45 { return true }
    }
    return false
}

/// True if a ball resting near something that moves can get caught by it for a long time (for
/// example wedged between a blade and a wall). Such a hole is rejected.
func windmillTraps(_ hole: Hole) -> Bool {
    // The places worth testing: round each windmill, and along the path of each moving wall.
    var spots: [Vec] = []
    for w in hole.windmills {
        for i in 0..<72 {
            let a = Double(i) / 72 * 2 * .pi
            spots.append(w.center + Vec(cos(a), sin(a)) * (20 + Double(i % 6) * (w.length - 15) / 6))
        }
    }
    for m in hole.movers {
        var lo = Vec(.infinity, .infinity), hi = Vec(-.infinity, -.infinity)
        let period = 2 * Double.pi / m.speed
        for k in 0..<16 {
            let e = m.ends(at: period * Double(k) / 16 - m.phase / m.speed)
            for p in [e.a, e.b] { lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y); hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y) }
        }
        var y = lo.y - 14
        while y <= hi.y + 14 {
            var x = lo.x - 14
            while x <= hi.x + 14 { spots.append(Vec(x, y)); x += 16 }
            y += 16
        }
    }
    for spot in spots {
        guard Poly.contains(hole.outline, spot), spot.distance(to: hole.cup) > 14 else { continue }
        var sim = Simulation(hole: hole)
        sim.pos = spot
        var events: [SimEvent] = []
        var lastContact = 0
        for step in 0..<(240 * 20) {
            events.removeAll(keepingCapacity: true)
            if sim.isMoving { _ = sim.step(events: &events) } else { sim.restStep(events: &events) }
            for e in events { if case .windmill = e { lastContact = step } }
        }
        // A ball that is knocked a few times is soon clear of it. One that is carried along or
        // squeezed against a wall is still being hit long after (more than 12 seconds in).
        if lastContact > 240 * 12 { return true }
    }
    return false
}

/// Whether the obstacle a recipe asked for is really on the hole (some do not fit a narrow
/// course, and then the generator quietly leaves them out).
func placed(_ m: Middle, in h: Hole) -> Bool {
    func hasPatch(_ f: (SurfaceKind) -> Bool) -> Bool { h.patches.contains { f($0.kind) } }
    switch m {
    case .gate, .pillars, .bar: return true
    case .sand: return hasPatch { if case .sand = $0 { return true } else { return false } }
    case .ice: return hasPatch { if case .ice = $0 { return true } else { return false } }
    case .mud: return hasPatch { if case .mud = $0 { return true } else { return false } }
    case .pond: return hasPatch { if case .water = $0 { return true } else { return false } }
    case .lava: return hasPatch { if case .lava = $0 { return true } else { return false } }
    case .wind: return hasPatch { if case .wind = $0 { return true } else { return false } }
    case .slope: return hasPatch { if case .slope = $0 { return true } else { return false } }
    case .boost: return hasPatch { if case .boost = $0 { return true } else { return false } }
    case .bridge: return hasPatch { if case .bridge = $0 { return true } else { return false } }
    case .jump: return hasPatch { if case .ramp = $0 { return true } else { return false } }
    case .bumpers: return !h.bumpers.isEmpty
    case .windmill: return h.windmills.contains { $0.style == .windmill }
    case .spinner: return h.windmills.contains { $0.style == .spinner }
    case .magnet: return !h.magnets.isEmpty
    case .portal: return h.portals.contains { !$0.isTunnel }
    case .tunnel: return h.portals.contains { $0.isTunnel }
    case .slider: return h.movers.contains { if case .slide = $0.motion { return $0.thickness <= 18 } else { return false } }
    case .piston: return h.movers.contains { if case .slide = $0.motion { return $0.thickness > 18 } else { return false } }
    case .pendulum: return h.movers.contains { if case .swing = $0.motion { return true } else { return false } }
    case .oneWay: return !h.oneWays.isEmpty
    case .door: return !h.doors.isEmpty
    case .springBars: return !h.bouncePads.isEmpty
    case .brickWall: return !h.breakables.isEmpty
    }
}

/// How many different features the winning route of a level has to meet, so a hole cannot be beaten
/// by simply going around its obstacles.
func requiredEngagement(level: Int) -> Int {
    let step = HoleGenerator.step(forLevel: level)
    return level <= 50 ? 0 : step >= 7 ? 3 : step >= 3 ? 2 : 1
}

/// How much of the wide neighbourhood of the best shot may still sink: at the later steps the
/// winning shot has to be fairly exact.
func maxWideWindow(level: Int) -> Double {
    let step = HoleGenerator.step(forLevel: level)
    return step >= 5 ? 0.95 - 0.05 * Double(step - 5) : 1.0
}

/// How many strokes a level should take at the very least, so the game gets harder as it goes.
func minimumStrokes(level: Int, template: Template? = nil) -> Int {
    let step = HoleGenerator.step(forLevel: level)
    // Only the long winding course can be made to ask for more shots; asking the others for 4 or
    // 5 just burns attempts (the world is small and a hard shot crosses it). They may still need
    // more shots naturally, thanks to doors, portals and the like.
    if level > 50, template == .snake { return step >= 2 ? 4 : 3 }
    switch HoleGenerator.tier(forLevel: level) {
    case 1: return 2
    case 2: return level % 2 == 0 ? 3 : 2
    default: return 3
    }
}

func acceptable(_ r: Report, level: Int, template: Template, relaxed: Bool, desperate: Bool = false, hazardCap: Double = 0.55) -> Bool {
    guard let optimal = r.optimal else { return false }
    let step = HoleGenerator.step(forLevel: level)
    let maxOptimal = (level <= 25 ? 3 : level <= 38 ? 4 : 5) + step / 2
    // Past the warm-up the stroke count is never relaxed, or the difficulty steps would not hold.
    let wanted = minimumStrokes(level: level, template: template)
    let minOptimal = relaxed ? max(step == 0 ? 2 : 3, wanted - 1) : wanted
    return optimal >= minOptimal && optimal <= maxOptimal
        && r.window >= (relaxed ? 0.15 - 0.01 * Double(step) : 0.22 - 0.015 * Double(step))
        && r.hazardRate <= hazardCap
        && r.trapRate <= 0.2
        && r.hasWideLane
        && r.clockSafe
        && (desperate || (!r.bypassable && r.wideWindow <= maxWideWindow(level: level) && (level <= 50 || r.wideWindow >= 0.3)))
}

/// Shapes and lead obstacles are dealt out in turn, so every kind turns up about equally often.
func scheduled(level: Int) -> (Template, Middle) {
    let i = level - options.from
    let shapes = HoleGenerator.templates(tier: HoleGenerator.tier(forLevel: level), level: level)
    return (shapes[(i * 5) % shapes.count], Middle.allCases[(i * 7 + i / 26) % Middle.allCases.count])
}

let started = Date()
for level in options.levels ?? Array(options.from...options.to) {
    let (wantedTemplate, wantedMiddle) = scheduled(level: level)
    var attempt = 0
    var found: Accepted?
    var triedSimilar = 0, triedInvalid = 0, triedRejected = 0
    while found == nil, attempt < options.attempts {
        let relaxed = attempt >= options.attempts / 2
        let dropLead = attempt >= (HoleGenerator.step(forLevel: level) > 0 ? options.attempts / 3 : options.attempts * 3 / 4)
        let batch = 8
        var evals = [Evaluation?](repeating: nil, count: batch)
        let base = UInt64(level) * 100_000 + UInt64(attempt)
        let snapshotSeen = seen
        let snapshotTemplates = templateUse, snapshotMiddles = middleUse
        evals.withUnsafeMutableBufferPointer { buffer in
            let out = buffer
            DispatchQueue.concurrentPerform(iterations: batch) { i in
                let seed = base + UInt64(i)
                let forced: Middle? = dropLead ? nil : wantedMiddle
                guard let gen = HoleGenerator.make(level: level, seed: seed, template: wantedTemplate, middle: forced) else { return }
                if forced != nil, !placed(wantedMiddle, in: gen.hole) { return }
                if snapshotTemplates[gen.template, default: 0] >= templateCap { return }
                if gen.middles.contains(where: { snapshotMiddles[$0, default: 0] >= middleCap }) { return }
                let fp = Fingerprint(gen.hole)
                var similar = false
                for other in snapshotSeen {
                    let s = fp.similarity(to: other)
                    if s.shape >= 0.88, s.features >= 0.45 { similar = true; break }
                }
                if similar { out[i] = Evaluation(seed: seed, forcedMiddle: forced, gen: gen, fingerprint: fp, report: nil); return }
                let checker = Checker(gen.hole)
                if HoleGenerator.step(forLevel: level) > 0 || level > 50 {
                    checker.strict = true
                    checker.minEngaged = requiredEngagement(level: level)
                }
                out[i] = Evaluation(seed: seed, forcedMiddle: forced, gen: gen, fingerprint: fp, report: checker.analyze())
            }
        }
        attempt += batch
        for e in evals {
            guard let e else { triedInvalid += 1; continue }
            guard let report = e.report else { triedSimilar += 1; continue }
            let crossesWater = e.gen.middles.contains(.bridge) || e.gen.middles.contains(.jump)
            guard acceptable(report, level: level, template: e.gen.template, relaxed: relaxed, desperate: attempt > options.attempts * 7 / 8, hazardCap: crossesWater ? 0.85 : 0.55), !isTooSimilar(e.fingerprint), !windmillTraps(e.gen.hole) else { triedRejected += 1; continue }
            // Worlds: the best fit for the recipe that was not used in the last two levels.
            let recent = accepted.suffix(2).map(\.theme)
            let theme = HoleGenerator.themeCandidates(for: e.gen).first { !recent.contains($0) } ?? .meadow
            let par = max(2, (report.optimal ?? 2) + 1)
            found = Accepted(level: level, seed: e.seed, theme: theme, par: par, gen: e.gen, fingerprint: e.fingerprint, report: report, forcedMiddle: e.forcedMiddle)
            break
        }
    }
    if let f = found {
        accepted.append(f)
        seen.append(f.fingerprint)
        templateUse[f.gen.template, default: 0] += 1
        for m in f.gen.middles { middleUse[m, default: 0] += 1 }
        let mids = f.gen.middles.map { "\($0)" }.joined(separator: "+")
        print(String(format: "level %2d  %-9@ %-24@ finish %-12@ optimal %d  window %.2f  wide %.2f  engaged %d  hazards %.2f  seed %llu  (tried %d)",
                     level, "\(f.gen.template)" as NSString, mids as NSString, "\(f.gen.finale)" as NSString,
                     f.report.optimal ?? 0, f.report.window, f.report.wideWindow, f.report.engaged, f.report.hazardRate, f.seed, attempt))
    } else {
        print("level \(level): NO HOLE FOUND after \(attempt) seeds (invalid \(triedInvalid), similar \(triedSimilar), rejected \(triedRejected))")
        if options.levels == nil { exit(1) }
    }
}
print(String(format: "Done in %.0fs.", Date().timeIntervalSince(started)))

if let sheet = options.sheet {
    let holes = accepted.compactMap { a in HoleGenerator.make(level: a.level, seed: a.seed, theme: a.theme, par: a.par, template: a.gen.template, middle: a.forcedMiddle)?.hole }
    writeSheet(holes, to: sheet)
    print("Wrote contact sheet of \(holes.count) holes to \(sheet)")
}

if let path = options.samples {
    var text = """
    //
    //  DifficultySamples.swift
    //  Tiny Putt
    //
    //  Written by the hole checker (--levels ... --samples). One proven hole per difficulty step, kept
    //  at far-off level numbers so they can be play-tested with the debug menu's "Go to hole".
    //  Do not edit by hand.
    //

    nonisolated enum DifficultySamples {
        static let entries: [Int: CampaignTable.Entry] = [

    """
    for a in accepted {
        text += "        \(a.level): CampaignTable.Entry(seed: \(a.seed), theme: \(a.theme.rawValue), par: \(a.par), template: \(a.gen.template.rawValue), middle: \(a.forcedMiddle?.rawValue ?? -1)),\n"
    }
    text += "    ]\n}\n"
    try! text.write(toFile: path, atomically: true, encoding: .utf8)
    print("Wrote \(accepted.count) samples to \(path)")
}

if let path = options.out {
    var text = """
    //
    //  CampaignTable.swift
    //  Tiny Putt
    //
    //  Written by the hole checker (Tools/HoleChecker). Each entry is a seed the checker proved
    //  makes a finishable, distinct hole, with the world it was given and the par it worked out.
    //  Do not edit by hand.
    //

    nonisolated enum CampaignTable {
        struct Entry: Sendable {
            let seed: UInt64
            let theme: Int
            let par: Int
            let template: Int
            /// The obstacle the checker asked for first (-1 for none), part of what the seed means.
            let middle: Int
        }

        /// Levels \(options.from) and up (levels 1-\(options.from - 1) are the hand-made holes).
        static let entries: [Entry] = [

    """
    for a in accepted {
        text += "        Entry(seed: \(a.seed), theme: \(a.theme.rawValue), par: \(a.par), template: \(a.gen.template.rawValue), middle: \(a.forcedMiddle?.rawValue ?? -1)),\n"
    }
    text += "    ]\n}\n"
    try! text.write(toFile: path, atomically: true, encoding: .utf8)
    print("Wrote \(accepted.count) levels to \(path)")
}
