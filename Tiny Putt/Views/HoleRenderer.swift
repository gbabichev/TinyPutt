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
        let t = ViewTransform(world: hole.size, view: size)

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(pal.rough))

        var w = ctx
        w.concatenate(t.affine)

        for item in game.scenery(for: t.visibleWorldRect(for: size)) {
            w.drawScenery(item, palette: pal, theme: hole.theme)
        }

        drawFairway(&w, hole: hole, pal: pal)
        for patch in hole.patches { drawPatch(&w, patch, pal: pal, time: time) }
        drawTee(&w, hole: hole)
        drawCup(&w, hole: hole)
        for block in hole.blocks { drawBlock(&w, block, pal: pal) }
        for m in hole.magnets { drawMagnet(&w, m, pal: pal, time: time) }
        for (i, b) in hole.bumpers.enumerated() {
            drawBumper(&w, b, pal: pal, pulse: i < game.bumperPulse.count ? game.bumperPulse[i] : 0)
        }

        drawRipples(&w, game: game)
        if let ball = game.displayBall {
            drawBall(&w, at: ball.pos, scale: ball.scale, color: game.ballColor.color)
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
            w.fill(outline, with: .color(pal.water))
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
                inside.stroke(p, with: .color(pal.waterLine.opacity(0.55)), lineWidth: 1.6)
                y += 13
                row += 1
            }
            w.stroke(outline, with: .color(pal.waterEdge), lineWidth: 3.5)
            w.stroke(outline, with: .color(pal.rim.opacity(0.9)), lineWidth: 1.2)
        case .lava:
            w.fill(outline, with: .color(pal.lava))
            for i in 0..<9 {
                let fx = Double(i) * 1.7
                let bx = lo.x + (hi.x - lo.x) * CGFloat(0.5 + 0.42 * sin(time * 0.5 + fx * 2.1))
                let by = lo.y + (hi.y - lo.y) * CGFloat(0.5 + 0.42 * cos(time * 0.4 + fx * 1.3))
                inside.fill(w.circle(CGPoint(x: bx, y: by), 9 + CGFloat(i % 3) * 3), with: .color(pal.lavaGlow.opacity(0.75)))
            }
            w.stroke(outline, with: .color(pal.lavaEdge), lineWidth: 4)
            w.stroke(outline, with: .color(pal.lavaGlow.opacity(0.7)), lineWidth: 1.5)
        case .slope(let a):
            inside.fill(outline, with: .color(.white.opacity(0.10)))
            chevrons(&inside, patch: patch, dir: Vec(a.x, a.y).normalized, time: time, color: .white.opacity(0.4), spacing: 34, speed: 18)
            w.stroke(outline, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
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

    private static func chevrons(_ ctx: inout GraphicsContext, patch: Patch, dir: Vec, time: Double, color: Color, spacing: Double, speed: Double) {
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
        w.fill(hub, with: .color(pal.bumper))
        w.stroke(hub, with: .color(.black.opacity(0.18)), lineWidth: 1.5)
        w.fill(w.circle(c, CGFloat(m.hub) * 0.4), with: .color(Color(hex: 0x8B2F2F)))
    }

    // MARK: - Ball and aiming

    private static func drawBall(_ w: inout GraphicsContext, at p: Vec, scale: Double, color: Color) {
        guard scale > 0.01 else { return }
        let c = p.cg
        let r = CGFloat(Simulation.ballRadius * scale)
        w.fill(w.circle(CGPoint(x: c.x + 1.5, y: c.y + 2.5), r), with: .color(.black.opacity(0.28)))
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
        let dir = pull.normalized
        let tint = Color(hue: 0.33 * (1 - power), saturation: 0.75, brightness: 0.98)

        // The power ring around the ball.
        let ringR: CGFloat = 17
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

        // The arrow, pointing the way the ball will go.
        let start = game.sim.pos + dir * 26
        let end = start + dir * (18 + 70 * power)
        var shaft = Path()
        shaft.move(to: start.cg)
        shaft.addLine(to: end.cg)
        let head = Path { p in
            p.move(to: (end + dir * 12).cg)
            p.addLine(to: (end + dir.perp * 8).cg)
            p.addLine(to: (end - dir.perp * 8).cg)
            p.closeSubpath()
        }
        w.stroke(shaft, with: .color(.black.opacity(0.3)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        w.fill(head, with: .color(.black.opacity(0.3)))
        w.stroke(head, with: .color(.black.opacity(0.3)), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        w.stroke(shaft, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        w.fill(head, with: .color(.white))

        // A rough idea of where it will stop.
        if let e = game.estimate {
            let c = e.center.cg
            w.fill(w.circle(c, CGFloat(e.radius)), with: .color(.white.opacity(0.16)))
            w.stroke(w.circle(c, CGFloat(e.radius)), with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
        }
    }
}
