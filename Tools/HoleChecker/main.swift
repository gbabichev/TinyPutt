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
//      "Tiny Putt/Engine/HoleGenerator.swift" "Tiny Putt/Engine/HoleLibrary.swift" "Tiny Putt/Engine/CampaignTable.swift"
//    /tmp/holechecker --from 11 --to 50 --out "Tiny Putt/Engine/CampaignTable.swift"
//

import Foundation

struct Options {
    var from = 11, to = 50
    var out: String?
    var attempts = 400
    var sheet: String?
    var solve: Int?
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
                     100 * pow(max(0, (step.shot.speed - Shot.minSpeed) / (Shot.maxSpeed - Shot.minSpeed)), 1 / 1.25), step.shot.offset))
        routes.append(checker.trace(from: step.from, step.shot))
    }
    if let sheet = options.sheet { writeSheet([hole], to: sheet, columns: 1, cell: 900, paths: routes) }
    exit(0)
}
var accepted: [Accepted] = []
var seen: [Fingerprint] = HoleLibrary.handMade.map { Fingerprint($0) }
var templateUse: [Template: Int] = [:]
var middleUse: [Middle: Int] = [:]
let templateCap = max(6, (options.to - options.from + 1) / 6)
let middleCap = max(8, (options.to - options.from + 1) / 4)

func isTooSimilar(_ f: Fingerprint) -> Bool {
    for other in seen {
        let s = f.similarity(to: other)
        if s.shape >= 0.88, s.features >= 0.45 { return true }
    }
    return false
}

/// True if a ball resting near a windmill can get caught by its blades for a long time (for
/// example wedged between a blade and a wall). Such a hole is rejected.
func windmillTraps(_ hole: Hole) -> Bool {
    for w in hole.windmills {
        for i in 0..<72 {
            var sim = Simulation(hole: hole)
            let a = Double(i) / 72 * 2 * .pi
            sim.pos = w.center + Vec(cos(a), sin(a)) * (20 + Double(i % 6) * (w.length - 15) / 6)
            if !Poly.contains(hole.outline, sim.pos) || sim.pos.distance(to: hole.cup) < 14 { continue }
            var events: [SimEvent] = []
            var inside = 0.0
            for _ in 0..<(240 * 25) {
                events.removeAll(keepingCapacity: true)
                if sim.isMoving { _ = sim.step(events: &events) } else { sim.restStep(events: &events) }
                if (sim.pos - w.center).length < w.length + 8 { inside += Simulation.dt }
            }
            if inside > 12 { return true }
        }
    }
    return false
}

/// How many strokes a level should take at the very least, so the game gets harder as it goes.
func minimumStrokes(level: Int) -> Int {
    switch HoleGenerator.tier(forLevel: level) {
    case 1: return 2
    case 2: return level % 2 == 0 ? 3 : 2
    default: return 3
    }
}

func acceptable(_ r: Report, level: Int, relaxed: Bool) -> Bool {
    guard let optimal = r.optimal else { return false }
    let maxOptimal = level <= 25 ? 3 : level <= 38 ? 4 : 5
    let minOptimal = relaxed ? max(2, minimumStrokes(level: level) - 1) : minimumStrokes(level: level)
    return optimal >= minOptimal && optimal <= maxOptimal
        && r.window >= (relaxed ? 0.15 : 0.22)
        && r.hazardRate <= 0.55
        && r.trapRate <= 0.2
}

/// Shapes and lead obstacles are dealt out in turn, so every kind turns up about equally often.
func scheduled(level: Int) -> (Template, Middle) {
    let i = level - options.from
    let shapes = HoleGenerator.templates(tier: HoleGenerator.tier(forLevel: level))
    return (shapes[(i * 5) % shapes.count], Middle.allCases[(i * 5 + i / 13) % Middle.allCases.count])
}

let started = Date()
for level in options.from...options.to {
    let (wantedTemplate, wantedMiddle) = scheduled(level: level)
    var attempt = 0
    var found: Accepted?
    var triedSimilar = 0, triedInvalid = 0, triedRejected = 0
    while found == nil, attempt < options.attempts {
        let relaxed = attempt >= options.attempts / 2
        let batch = 8
        var evals = [Evaluation?](repeating: nil, count: batch)
        let base = UInt64(level) * 100_000 + UInt64(attempt)
        let snapshotSeen = seen
        let snapshotTemplates = templateUse, snapshotMiddles = middleUse
        evals.withUnsafeMutableBufferPointer { buffer in
            let out = buffer
            DispatchQueue.concurrentPerform(iterations: batch) { i in
                let seed = base + UInt64(i)
                let forced: Middle? = relaxed ? nil : wantedMiddle
                guard let gen = HoleGenerator.make(level: level, seed: seed, template: wantedTemplate, middle: forced) else { return }
                if snapshotTemplates[gen.template, default: 0] >= templateCap { return }
                if gen.middles.contains(where: { snapshotMiddles[$0, default: 0] >= middleCap }) { return }
                let fp = Fingerprint(gen.hole)
                var similar = false
                for other in snapshotSeen {
                    let s = fp.similarity(to: other)
                    if s.shape >= 0.88, s.features >= 0.45 { similar = true; break }
                }
                if similar { out[i] = Evaluation(seed: seed, forcedMiddle: forced, gen: gen, fingerprint: fp, report: nil); return }
                out[i] = Evaluation(seed: seed, forcedMiddle: forced, gen: gen, fingerprint: fp, report: Checker(gen.hole).analyze())
            }
        }
        attempt += batch
        for e in evals {
            guard let e else { triedInvalid += 1; continue }
            guard let report = e.report else { triedSimilar += 1; continue }
            guard acceptable(report, level: level, relaxed: relaxed), !isTooSimilar(e.fingerprint), !windmillTraps(e.gen.hole) else { triedRejected += 1; continue }
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
        print(String(format: "level %2d  %-9@ %-24@ finish %-12@ optimal %d  window %.2f  hazards %.2f  seed %llu  (tried %d)",
                     level, "\(f.gen.template)" as NSString, mids as NSString, "\(f.gen.finale)" as NSString,
                     f.report.optimal ?? 0, f.report.window, f.report.hazardRate, f.seed, attempt))
    } else {
        print("level \(level): NO HOLE FOUND after \(attempt) seeds (invalid \(triedInvalid), similar \(triedSimilar), rejected \(triedRejected))")
        exit(1)
    }
}
print(String(format: "Done in %.0fs.", Date().timeIntervalSince(started)))

if let sheet = options.sheet {
    let holes = accepted.compactMap { a in HoleGenerator.make(level: a.level, seed: a.seed, theme: a.theme, par: a.par, template: a.gen.template, middle: a.forcedMiddle)?.hole }
    writeSheet(holes, to: sheet)
    print("Wrote contact sheet of \(holes.count) holes to \(sheet)")
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
