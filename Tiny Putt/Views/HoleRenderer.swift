//
//  HoleRenderer.swift
//  Tiny Putt
//
//  Draws a hole with flat shapes: a rough, a cream-rimmed fairway, hazards and gadgets, the
//  ball, and the aiming overlay.
//

import SwiftUI

enum HoleRenderer {
    private static let rimWidth: CGFloat = 11

    static func path(_ pts: [Vec]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first.cg)
        for q in pts.dropFirst() { p.addLine(to: q.cg) }
        p.closeSubpath()
        return p
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, game: GolfGame) {
        let hole = game.hole
        let pal = hole.theme.palette
        let time = game.animTime
        let t = game.transform(for: size)

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(pal.rough))

        var w = ctx
        w.concatenate(t.affine)

        for item in game.scenery(for: t.visibleWorldRect(for: size)) {
            w.drawScenery(item, palette: pal, theme: hole.theme)
        }

        drawFairway(&w, hole: hole, pal: pal)
        // Hazards and surfaces are cut off at the edge of the course, never spilling over the rim.
        var onCourse = w
        onCourse.clip(to: path(hole.outline))
        // Dishes and hills lie under the other surfaces, so water and sand are never covered.
        for bowl in hole.bowls { drawBowl(&onCourse, bowl, time: time) }
        for patch in hole.patches { drawPatch(&onCourse, patch, pal: pal, time: time) }
        drawTee(&w, hole: hole)
        drawCup(&w, hole: hole)
        // Walls inside the course end flush with its edge.
        for block in hole.blocks { drawBlock(&onCourse, block, pal: pal) }
        for m in hole.magnets { drawMagnet(&w, m, pal: pal, time: time) }
        drawGadgets(&w, &onCourse, game: game, pal: pal, time: time)
        for (i, b) in hole.bumpers.enumerated() {
            drawBumper(&w, b, pal: pal, pulse: i < game.bumperPulse.count ? game.bumperPulse[i] : 0)
        }

        drawRipples(&w, game: game)
        if let ball = game.displayBall {
            drawBall(&w, at: ball.pos, scale: ball.scale, lift: ball.lift, color: game.ballColor.color)
        }
        if let pull = game.aimPull { drawAim(&w, game: game, pull: pull) }
        for wm in hole.windmills { drawWindmill(&w, wm, pal: pal, time: game.sim.time) }
        drawFlag(&w, hole: hole, pal: pal, time: time, rotated: t.rotated)
    }

    // MARK: - Ground

    private static func drawFairway(_ w: inout GraphicsContext, hole: Hole, pal: Palette) {
        let outline = path(hole.outline)
        w.fill(outline.offsetBy(dx: 0, dy: 5), with: .color(.black.opacity(0.18)))
        w.stroke(outline.offsetBy(dx: 0, dy: 3), with: .color(.black.opacity(0.12)),
                 style: StrokeStyle(lineWidth: rimWidth * 2, lineJoin: .round))
        w.stroke(outline, with: .color(pal.rim), style: StrokeStyle(lineWidth: rimWidth * 2, lineJoin: .round))
        w.stroke(outline, with: .color(pal.rimShade), style: StrokeStyle(lineWidth: rimWidth * 2 + 3, lineJoin: .round))
        w.stroke(outline, with: .color(pal.rim), style: StrokeStyle(lineWidth: rimWidth * 2 - 2, lineJoin: .round))
        w.fill(outline, with: .color(pal.fairway))

        var inside = w
        inside.clip(to: outline)
        // Mown stripes.
        let b = Poly.bounds(hole.outline)
        var x = b.lo.x - (b.hi.y - b.lo.y)
        var odd = false
        while x < b.hi.x {
            odd.toggle()
            if odd {
                var band = Path()
                band.addLines([
                    CGPoint(x: x, y: b.hi.y + 20), CGPoint(x: x + 36, y: b.hi.y + 20),
                    CGPoint(x: x + 36 + (b.hi.y - b.lo.y + 40) * 0.5, y: b.lo.y - 20),
                    CGPoint(x: x + (b.hi.y - b.lo.y + 40) * 0.5, y: b.lo.y - 20),
                ])
                band.closeSubpath()
                inside.fill(band, with: .color(.white.opacity(0.07)))
            }
            x += 36
        }
        inside.stroke(outline, with: .color(.black.opacity(0.14)), lineWidth: 10)
    }

    private static func drawTee(_ w: inout GraphicsContext, hole: Hole) {
        let r = CGRect(x: hole.tee.x - 17, y: hole.tee.y - 15, width: 34, height: 30)
        w.fill(Path(roundedRect: r, cornerRadius: 7), with: .color(.black.opacity(0.22)))
        w.stroke(Path(roundedRect: r, cornerRadius: 7), with: .color(.white.opacity(0.28)), lineWidth: 1.5)
    }

    private static func drawCup(_ w: inout GraphicsContext, hole: Hole) {
        let c = hole.cup.cg
        w.fill(w.circle(c, Simulation.cupRadius + 3), with: .color(.black.opacity(0.18)))
        w.fill(w.circle(c, Simulation.cupRadius), with: .color(Color(hex: 0x15251C)))
        w.stroke(w.circle(c, Simulation.cupRadius), with: .color(.white.opacity(0.75)), lineWidth: 2)
    }

    private static func drawFlag(_ w: inout GraphicsContext, hole: Hole, pal: Palette, time: Double, rotated: Bool) {
        var f = w
        f.translateBy(x: hole.cup.x, y: hole.cup.y)
        // Keep the flag upright on screen even when the hole is turned.
        if rotated { f.rotate(by: .degrees(-90)) }
        let top = CGPoint(x: -2, y: -38)
        var pole = Path()
        pole.move(to: CGPoint(x: 0, y: 0))
        pole.addLine(to: top)
        f.stroke(pole.offsetBy(dx: 3, dy: 3), with: .color(.black.opacity(0.16)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        f.stroke(pole, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        let wave = CGFloat(sin(time * 3.2)) * 2
        var flag = Path()
        flag.move(to: top)
        flag.addQuadCurve(to: CGPoint(x: top.x + 24, y: top.y + 6 + wave), control: CGPoint(x: top.x + 12, y: top.y + wave))
        flag.addLine(to: CGPoint(x: top.x, y: top.y + 14))
        flag.closeSubpath()
        f.fill(flag, with: .color(pal.flag))
    }

    // MARK: - Hazards and surfaces

    private static func drawPatch(_ w: inout GraphicsContext, _ patch: Patch, pal: Palette, time: Double) {
        let outline = path(patch.outline)
        let lo = patch.lo, hi = patch.hi
        var inside = w
        inside.clip(to: outline)

        switch patch.kind {
        case .sand:
            w.fill(outline, with: .color(pal.sand))
            var y = lo.y
            while y < hi.y {
                var x = lo.x
                while x < hi.x {
                    let jx = CGFloat(sin(x * 12.9 + y * 78.2)) * 5, jy = CGFloat(cos(x * 39.3 + y * 11.1)) * 5
                    inside.fill(w.circle(CGPoint(x: x + jx, y: y + jy), 1.3), with: .color(pal.sandDot))
                    x += 13
                }
                y += 13
            }
            w.stroke(outline, with: .color(pal.sandDot), lineWidth: 2.5)
        case .mud:
            w.fill(outline, with: .color(pal.mud))
            w.stroke(outline, with: .color(.black.opacity(0.3)), lineWidth: 2.5)
        case .ice:
            w.fill(outline, with: .color(pal.ice))
            var x = lo.x - (hi.y - lo.y)
            while x < hi.x {
                var p = Path()
                p.move(to: CGPoint(x: x, y: hi.y))
                p.addLine(to: CGPoint(x: x + (hi.y - lo.y), y: lo.y))
                inside.stroke(p, with: .color(pal.iceLine.opacity(0.75)), lineWidth: 3)
                x += 22
            }
            w.stroke(outline, with: .color(pal.iceEdge), lineWidth: 3)
        case .water:
            let centre = CGPoint(x: (lo.x + hi.x) / 2, y: (lo.y + hi.y) / 2)
            let reach = max(hi.x - lo.x, hi.y - lo.y) * 0.6
            w.fill(outline, with: .radialGradient(Gradient(colors: [pal.waterDeep, pal.water]), center: centre, startRadius: 0, endRadius: reach))
            // Shallow water along the shore.
            inside.stroke(outline, with: .color(pal.waterShallow.opacity(0.75)), style: StrokeStyle(lineWidth: 16, lineJoin: .round))
            inside.stroke(outline, with: .color(pal.waterShallow.opacity(0.5)), style: StrokeStyle(lineWidth: 26, lineJoin: .round))
            var y = lo.y + 8
            var row = 0
            while y < hi.y {
                var p = Path()
                var x = lo.x - 10
                p.move(to: CGPoint(x: x, y: y))
                while x < hi.x + 10 {
                    x += 6
                    p.addLine(to: CGPoint(x: x, y: y + CGFloat(sin(Double(x) * 0.18 + time * 2 + Double(row))) * 2.2))
                }
                inside.stroke(p, with: .color(pal.waterLine.opacity(0.5)), lineWidth: 1.6)
                y += 13
                row += 1
            }
            // Glints.
            for i in 0..<6 {
                let fx = (Double(i) * 0.37 + 0.13).truncatingRemainder(dividingBy: 1)
                let fy = (Double(i) * 0.61 + 0.29).truncatingRemainder(dividingBy: 1)
                let a = max(0, sin(time * 2.2 + Double(i) * 1.9))
                guard a > 0.05 else { continue }
                let c = CGPoint(x: lo.x + (hi.x - lo.x) * fx, y: lo.y + (hi.y - lo.y) * fy)
                inside.fill(inside.star(center: c, outer: 5 * CGFloat(a) + 1, inner: 1, points: 4), with: .color(.white.opacity(0.85 * a)))
            }
            // A stone edge.
            w.stroke(outline, with: .color(pal.stoneShade), style: StrokeStyle(lineWidth: 8, lineJoin: .round))
            w.stroke(outline, with: .color(pal.stone), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
        case .lava:
            let centre = CGPoint(x: (lo.x + hi.x) / 2, y: (lo.y + hi.y) / 2)
            let spanX = hi.x - lo.x, spanY = hi.y - lo.y
            let size = min(spanX, spanY)
            let reach = max(spanX, spanY) * 0.62
            let seed = Double(lo.x) * 0.013 + Double(lo.y) * 0.007
            // A faint warm haze on the ground around it.
            w.stroke(outline, with: .color(pal.lavaGlow.opacity(0.10)), style: StrokeStyle(lineWidth: 30, lineJoin: .round))
            w.stroke(outline, with: .color(pal.lavaGlow.opacity(0.12)), style: StrokeStyle(lineWidth: 16, lineJoin: .round))
            // Hot in the middle, cooling to deep red at the edge.
            w.fill(outline, with: .radialGradient(Gradient(colors: [pal.lavaGlow, pal.lava, pal.lavaDeep]), center: centre, startRadius: 0, endRadius: reach))
            // Slow, soft pools of heat that drift about.
            for i in 0..<3 {
                let fi = Double(i)
                let c = CGPoint(x: centre.x + CGFloat(sin(time * 0.21 + seed + fi * 2.1)) * spanX * 0.26,
                                y: centre.y + CGFloat(cos(time * 0.17 + seed * 1.3 + fi * 1.7)) * spanY * 0.26)
                let r = max(size * 0.5, 30)
                inside.fill(inside.circle(c, r), with: .radialGradient(Gradient(colors: [pal.lavaHot.opacity(0.55), pal.lavaGlow.opacity(0)]), center: c, startRadius: 0, endRadius: r))
            }
            // Slow, wavy streaks of brighter lava, like a current moving through it.
            var row = 0
            var y = lo.y + 10
            while y < hi.y {
                var streak = Path()
                var x = lo.x - 10
                streak.move(to: CGPoint(x: x, y: y))
                while x < hi.x + 10 {
                    x += 6
                    let wave = sin(Double(x) * 0.05 + time * 0.7 + Double(row) * 1.3 + seed) * 4
                    streak.addLine(to: CGPoint(x: x, y: y + CGFloat(wave)))
                }
                inside.stroke(streak, with: .color(pal.lavaHot.opacity(0.22)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                y += 20
                row += 1
            }
            // A few bubbles that swell and pop.
            for i in 0..<4 {
                let phase = (time * 0.32 + Double(i) * 0.27 + seed).truncatingRemainder(dividingBy: 1)
                let fx = (Double(i) * 0.43 + 0.17 + seed * 0.1).truncatingRemainder(dividingBy: 1)
                let fy = (Double(i) * 0.71 + 0.11 + seed * 0.07).truncatingRemainder(dividingBy: 1)
                let c = CGPoint(x: lo.x + spanX * (0.15 + 0.7 * CGFloat(fx)), y: lo.y + spanY * (0.15 + 0.7 * CGFloat(fy)))
                if phase < 0.8 {
                    let r = 1.5 + 5 * CGFloat(phase / 0.8)
                    inside.fill(inside.circle(c, r), with: .color(pal.lavaHot.opacity(0.85)))
                    inside.fill(inside.circle(CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), r * 0.35), with: .color(.white.opacity(0.7)))
                } else {
                    let t = CGFloat((phase - 0.8) / 0.2)
                    inside.stroke(inside.circle(c, 6 + 8 * t), with: .color(pal.lavaHot.opacity(0.7 * Double(1 - t))), lineWidth: 1.6)
                }
            }
            // The edge cools to a dark crust with a hot line just inside it.
            inside.stroke(outline, with: .color(pal.crust.opacity(0.35)), style: StrokeStyle(lineWidth: 22, lineJoin: .round))
            inside.stroke(outline, with: .color(pal.crust.opacity(0.55)), style: StrokeStyle(lineWidth: 11, lineJoin: .round))
            w.stroke(outline, with: .color(pal.crust), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
            inside.stroke(outline, with: .color(pal.lavaGlow.opacity(0.5 + 0.2 * sin(time * 1.1 + seed))), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        case .slope(let a):
            inside.fill(outline, with: .color(.white.opacity(0.10)))
            chevrons(&inside, patch: patch, dir: Vec(a.x, a.y).normalized, time: time, color: .white.opacity(0.4), spacing: 34, speed: 18)
            w.stroke(outline, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        case .boost(let dir):
            // A bright pad with arrows racing along it.
            w.fill(outline, with: .color(Color(hex: 0xFFC83D).opacity(0.55)))
            chevrons(&inside, patch: patch, dir: dir.normalized, time: time, color: .white.opacity(0.95), spacing: 18, speed: 70)
            w.stroke(outline, with: .color(Color(hex: 0xE08A00)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        case .bridge:
            drawBridge(&w, patch, pal: pal)
        case .ramp(let dir):
            // A wedge that rises toward its far end: dark at the foot, bright at the lip.
            let d = dir.normalized
            let a = Vec(Double(lo.x + hi.x) / 2, Double(lo.y + hi.y) / 2)
            let half = abs(d.x) * Double(hi.x - lo.x) / 2 + abs(d.y) * Double(hi.y - lo.y) / 2
            let p0 = (a - d * half).cg, p1 = (a + d * half).cg
            w.fill(outline, with: .linearGradient(Gradient(colors: [.black.opacity(0.40), .white.opacity(0.55)]), startPoint: p0, endPoint: p1))
            chevrons(&inside, patch: patch, dir: d, time: time, color: .white.opacity(0.85), spacing: 22, speed: 28)
            // A bright lip at the far end, where the ball takes off, with hazard-style stripes.
            let across = d.perp
            let wide = abs(across.x) * Double(hi.x - lo.x) / 2 + abs(across.y) * Double(hi.y - lo.y) / 2
            let lipAt = a + d * (half - 7)
            var lip = Path()
            lip.move(to: (lipAt + across * wide).cg)
            lip.addLine(to: (lipAt - across * wide).cg)
            inside.stroke(lip, with: .color(Color(hex: 0xFFB020)), style: StrokeStyle(lineWidth: 14))
            inside.stroke(lip, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 14, dash: [9, 9]))
            // Rails down both sides.
            for side in [-1.0, 1.0] {
                var rail = Path()
                rail.move(to: (a - d * half + across * (wide - 2) * side).cg)
                rail.addLine(to: (a + d * half + across * (wide - 2) * side).cg)
                inside.stroke(rail, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 4))
            }
            w.stroke(outline, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        case .wind(let a):
            for lane in stride(from: 0.0, to: 1.0, by: 0.11) {
                let dir = Vec(a.x, a.y).normalized
                let across = dir.perp
                let span = max(hi.x - lo.x, hi.y - lo.y)
                let centre = Vec((lo.x + hi.x) / 2, (lo.y + hi.y) / 2)
                for k in 0..<3 {
                    let phase = (time * 0.35 + lane * 3.7 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    let along = (phase - 0.5) * span * 1.6
                    let off = (lane - 0.5) * span * 1.5
                    let p0 = centre + dir * along + across * off
                    let p1 = p0 + dir * 30
                    var s = Path()
                    s.move(to: p0.cg)
                    s.addLine(to: p1.cg)
                    inside.stroke(s, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
            w.stroke(outline, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 2, dash: [3, 6]))
        }
    }

    static func chevrons(_ ctx: inout GraphicsContext, patch: Patch, dir: Vec, time: Double, color: Color, spacing: Double, speed: Double) {
        let across = dir.perp
        let centre = Vec((patch.lo.x + patch.hi.x) / 2, (patch.lo.y + patch.hi.y) / 2)
        let span = max(patch.hi.x - patch.lo.x, patch.hi.y - patch.lo.y)
        let shift = (time * speed).truncatingRemainder(dividingBy: spacing)
        var a = -span
        while a < span {
            var b = -span
            while b < span {
                let p = centre + dir * (a + shift) + across * b
                var s = Path()
                s.move(to: (p - dir * 5 + across * 7).cg)
                s.addLine(to: (p + dir * 4).cg)
                s.addLine(to: (p - dir * 5 - across * 7).cg)
                ctx.stroke(s, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                b += spacing
            }
            a += spacing
        }
    }

    // MARK: - Gadgets

    /// A dish or a hill. A dish is darker in the middle with arrows drifting in (the ground slopes
    /// down toward the cup, so the ball rolls that way). A hill is lighter on top with arrows
    /// drifting out (the ground slopes down away from the cup).
    private static func drawBowl(_ w: inout GraphicsContext, _ b: Bowl, time: Double) {
        let c = b.center.cg
        let r = CGFloat(b.radius)
        let disc = w.circle(c, r)
        let stops: [Gradient.Stop] = b.isHill
            ? [.init(color: .white.opacity(0.30), location: 0),
               .init(color: .white.opacity(0.10), location: 0.55),
               .init(color: .black.opacity(0.14), location: 1)]
            : [.init(color: .black.opacity(0.20), location: 0),
               .init(color: .black.opacity(0.06), location: 0.6),
               .init(color: .white.opacity(0.14), location: 1)]
        w.fill(disc, with: .radialGradient(Gradient(stops: stops), center: c, startRadius: 0, endRadius: r))
        w.stroke(disc, with: .color(.black.opacity(0.10)), lineWidth: 2)
        for f in [0.32, 0.58, 0.84] {
            w.stroke(w.circle(c, r * f), with: .color(.white.opacity(0.42)),
                     style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        let count = 10
        for k in 0..<count {
            let angle = Double(k) / Double(count) * 2 * .pi + 0.2
            let outward = Vec(cos(angle), sin(angle))
            let phase = (time * 0.32 + Double(k % 2) * 0.5).truncatingRemainder(dividingBy: 1)
            let radius = b.radius * (b.isHill ? 0.35 + 0.55 * phase : 0.9 - 0.55 * phase)
            let fade = sin(phase * .pi)
            let p = b.center + outward * radius
            let heading = b.isHill ? outward : outward * -1
            var chevron = Path()
            chevron.move(to: (p - heading * 6 + heading.perp * 9).cg)
            chevron.addLine(to: (p + heading * 5).cg)
            chevron.addLine(to: (p - heading * 6 - heading.perp * 9).cg)
            w.stroke(chevron, with: .color(.white.opacity(0.8 * fade)),
                     style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
        }
    }

    private static func drawBlock(_ w: inout GraphicsContext, _ block: [Vec], pal: Palette) {
        let p = path(block)
        w.fill(p.offsetBy(dx: 0, dy: 4), with: .color(.black.opacity(0.22)))
        w.fill(p, with: .color(pal.rim))
        w.stroke(p, with: .color(pal.rimShade), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
    }

    private static func drawBumper(_ w: inout GraphicsContext, _ b: Bumper, pal: Palette, pulse: Double) {
        let c = b.center.cg
        let r = CGFloat(b.radius) * (1 + CGFloat(pulse) * 0.14)
        w.fill(w.circle(CGPoint(x: c.x + 1.5, y: c.y + 4), r), with: .color(.black.opacity(0.25)))
        w.fill(w.circle(c, r), with: .color(pal.rim))
        w.fill(w.circle(c, r * 0.8), with: .color(pal.bumper))
        w.fill(w.circle(c, r * 0.5), with: .color(.white.opacity(0.22 + pulse * 0.5)))
        w.stroke(w.circle(c, r * 0.8), with: .color(.black.opacity(0.18)), lineWidth: 1.5)
    }

    private static func drawMagnet(_ w: inout GraphicsContext, _ m: Magnet, pal: Palette, time: Double) {
        let c = m.center.cg
        let attract = m.strength >= 0
        for k in 0..<3 {
            var phase = (time * 0.5 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            if attract { phase = 1 - phase }
            let r = CGFloat(m.radius) * CGFloat(0.25 + 0.75 * phase)
            w.stroke(w.circle(c, r), with: .color(.white.opacity(0.35 * sin(phase * .pi))), style: StrokeStyle(lineWidth: 2.5, dash: [6, 6]))
        }
        // A horseshoe.
        var u = Path()
        u.addArc(center: c, radius: 11, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        w.stroke(u.offsetBy(dx: 1.5, dy: 3), with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
        w.stroke(u, with: .color(Color(hex: 0xD93B3B)), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
        var tips = Path()
        for sx in [-11.0, 11.0] {
            tips.move(to: CGPoint(x: c.x + sx, y: c.y))
            tips.addLine(to: CGPoint(x: c.x + sx, y: c.y - 9))
        }
        w.stroke(tips, with: .color(Color(hex: 0xD93B3B)), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
        var caps = Path()
        for sx in [-11.0, 11.0] {
            caps.move(to: CGPoint(x: c.x + sx, y: c.y - 9))
            caps.addLine(to: CGPoint(x: c.x + sx, y: c.y - 13))
        }
        w.stroke(caps, with: .color(.white), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
    }

    private static func drawWindmill(_ w: inout GraphicsContext, _ m: Windmill, pal: Palette, time: Double) {
        let c = m.center.cg
        for k in 0..<m.blades {
            var blade = Path()
            blade.move(to: c)
            blade.addLine(to: m.tip(of: k, at: time).cg)
            w.stroke(blade.offsetBy(dx: 3, dy: 5), with: .color(.black.opacity(0.2)), style: StrokeStyle(lineWidth: m.thickness, lineCap: .butt))
            w.stroke(blade, with: .color(pal.woodEdge), style: StrokeStyle(lineWidth: m.thickness, lineCap: .butt))
            w.stroke(blade, with: .color(pal.wood), style: StrokeStyle(lineWidth: m.thickness - 3, lineCap: .butt))
            w.stroke(blade, with: .color(pal.woodEdge.opacity(0.6)), style: StrokeStyle(lineWidth: m.thickness - 4, lineCap: .butt, dash: [2, 6]))
        }
        let hub = w.star(center: c, outer: CGFloat(m.hub), inner: CGFloat(m.hub) * 0.92, points: 8, rotation: .pi / 8)
        w.fill(hub.offsetBy(dx: 2, dy: 4), with: .color(.black.opacity(0.25)))
        w.fill(hub, with: .color(m.style == .spinner ? Color(hex: 0x3B6FD6) : pal.bumper))
        w.stroke(hub, with: .color(.black.opacity(0.18)), lineWidth: 1.5)
        w.fill(w.circle(c, CGFloat(m.hub) * 0.4), with: .color(Color(hex: 0x8B2F2F)))
    }

    // MARK: - Ball and aiming

    private static func drawBall(_ w: inout GraphicsContext, at p: Vec, scale: Double, lift: Double = 0, color: Color) {
        guard scale > 0.01 else { return }
        let ground = p.cg
        let r = CGFloat(Simulation.ballRadius * scale)
        // The shadow stays on the ground (smaller and fainter the higher the ball is).
        let shadowR = lift > 0 ? CGFloat(Simulation.ballRadius) * (1 - CGFloat(lift) * 0.012) : r
        w.fill(w.circle(CGPoint(x: ground.x + 1.5, y: ground.y + 2.5), shadowR), with: .color(.black.opacity(lift > 0 ? 0.22 : 0.28)))
        let c = CGPoint(x: ground.x, y: ground.y - CGFloat(lift))
        w.fill(w.circle(c, r), with: .color(color))
        w.stroke(w.circle(c, r), with: .color(.black.opacity(0.22)), lineWidth: 1)
        w.fill(w.circle(CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), r * 0.32), with: .color(.white.opacity(0.65)))
    }

    private static func drawRipples(_ w: inout GraphicsContext, game: GolfGame) {
        guard game.phase == .hazard, game.hazardKind != .outOfBounds else { return }
        let t = min(1, game.phaseTime / 0.9)
        let color: Color = game.hazardKind == .water ? .white : Color(hex: 0xFFB03A)
        for k in 0..<2 {
            let tt = max(0, min(1, t - Double(k) * 0.18))
            guard tt > 0 else { continue }
            w.stroke(w.circle(game.hazardAt.cg, CGFloat(8 + 30 * tt)), with: .color(color.opacity(0.8 * (1 - tt))), lineWidth: 3)
        }
    }

    private static func drawAim(_ w: inout GraphicsContext, game: GolfGame, pull: Vec) {
        let ball = game.sim.pos.cg
        let power = Shot.power(forPull: pull.length)
        // Yellow when soft, shading to orange-red as the shot gets harder.
        let tint = Color(hue: 0.005 + 0.15 * (1 - power), saturation: 0.88, brightness: 1.0)

        // The power ring around the ball.
        let ringR: CGFloat = 13
        w.stroke(w.circle(ball, ringR), with: .color(.black.opacity(0.28)), lineWidth: 6)
        w.stroke(w.circle(ball, ringR), with: .color(.white.opacity(0.4)), lineWidth: 4)
        if power > 0.01 {
            var arc = Path()
            let steps = max(2, Int(power * 60))
            for i in 0...steps {
                let a = -Double.pi / 2 + Double(i) / Double(steps) * power * 2 * .pi
                let pt = CGPoint(x: ball.x + cos(a) * ringR, y: ball.y + sin(a) * ringR)
                if i == 0 { arc.move(to: pt) } else { arc.addLine(to: pt) }
            }
            w.stroke(arc, with: .color(tint), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }

        // The route of the shot as a trail of dots in the same colour, fading away along its length.
        if let preview = game.estimate, preview.points.count > 1 {
            var total = 0.0
            for i in 1..<preview.points.count { total += preview.points[i].distance(to: preview.points[i - 1]) }
            // Each dot sits at a fixed distance along the route and looks the same however long
            // the route is, so a wobbling pull never makes the trail flicker. Only the last dot
            // fades in or out smoothly as the end of the route moves past it. The first dot sits
            // just outside the power ring, so even a short route (a soft pull, or sand and mud
            // that stop the ball quickly) still shows a few dots.
            var nextDot = Double(ringR) + 3
            let gap = 9.0
            var travelled = 0.0
            for i in 1..<preview.points.count {
                let a = preview.points[i - 1], b = preview.points[i]
                let seg = a.distance(to: b)
                guard seg > 0 else { continue }
                while nextDot <= travelled + seg {
                    let p = a + (b - a) * ((nextDot - travelled) / seg)
                    let far = min(1, nextDot / 170)
                    let end = max(0, min(1, (total - nextDot + 4) / 8))
                    let ease = end * end * (3 - 2 * end)
                    w.fill(w.circle(p.cg, CGFloat(2.4 - 1.0 * far)), with: .color(tint.opacity((1 - 0.75 * far) * ease)))
                    nextDot += gap
                }
                travelled += seg
            }
        }
    }
}
