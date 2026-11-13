//
//  GadgetArt.swift
//  Tiny Putt
//
//  The look of the newer obstacles: portals and tunnels, moving walls, switches and doors,
//  one-way gates, springy bars and breakable blocks (bridges, speed pads and ramps are surfaces,
//  drawn with the other patches).
//

import SwiftUI

extension HoleRenderer {
    private static let portalColors = [Color(hex: 0xA855F7), Color(hex: 0x14B8A6), Color(hex: 0xF97316)]
    private static let doorColors = [Color(hex: 0xE5484D), Color(hex: 0x3B82F6), Color(hex: 0xF59E0B)]

    /// Everything that is not a surface, a bumper, a magnet or a windmill.
    static func drawGadgets(_ w: inout GraphicsContext, _ onCourse: inout GraphicsContext, game: GolfGame, pal: Palette, time: Double) {
        drawGadgets(&w, &onCourse, hole: game.hole, doorsOpen: game.sim.doorsOpen, broken: game.sim.broken, clock: game.sim.time, pal: pal, time: time)
    }

    static func drawGadgets(_ w: inout GraphicsContext, _ onCourse: inout GraphicsContext, hole: Hole, doorsOpen: UInt32, broken: UInt32, clock: Double, pal: Palette, time: Double) {
        for (i, door) in hole.doors.enumerated() {
            drawDoor(&onCourse, door, color: doorColors[i % doorColors.count], open: doorsOpen & (1 << UInt32(i)) != 0)
        }
        for (i, sw) in hole.switches.enumerated() {
            drawSwitch(&w, sw, color: doorColors[i % doorColors.count], pressed: doorsOpen & (1 << UInt32(i)) != 0)
        }
        for (i, br) in hole.breakables.enumerated() where broken & (1 << UInt32(i)) == 0 {
            drawBreakable(&onCourse, br, pal: pal)
        }
        for g in hole.oneWays { drawOneWay(&w, g, time: time) }
        for bar in hole.bouncePads { drawBouncePad(&w, bar) }
        for m in hole.movers { drawMover(&w, &onCourse, m, pal: pal, time: clock) }
        for (i, p) in hole.portals.enumerated() {
            let color = portalColors[i % portalColors.count]
            if p.isTunnel {
                w.stroke(linePath(p.a, p.b), with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 7]))
            }
            drawPortalEnd(&w, p.a, radius: p.radius, color: color, tunnel: p.isTunnel, time: time)
            drawPortalEnd(&w, p.b, radius: p.radius, color: color, tunnel: p.isTunnel, time: time + 0.4)
        }
    }

    private static func linePath(_ a: Vec, _ b: Vec) -> Path {
        var p = Path()
        p.move(to: a.cg)
        p.addLine(to: b.cg)
        return p
    }

    // MARK: Surfaces

    /// Planks across a river, with a rope rail down each side.
    static func drawBridge(_ w: inout GraphicsContext, _ patch: Patch, pal: Palette) {
        let outline = path(patch.outline)
        let lo = patch.lo, hi = patch.hi
        let alongX = (hi.x - lo.x) >= (hi.y - lo.y)
        var inside = w
        inside.clip(to: outline)
        w.fill(outline.offsetBy(dx: 0, dy: 3), with: .color(.black.opacity(0.25)))
        w.fill(outline, with: .color(Color(hex: 0xB9834A)))
        var k = alongX ? lo.x : lo.y
        let end = alongX ? hi.x : hi.y
        while k < end {
            var line = Path()
            if alongX {
                line.move(to: CGPoint(x: k, y: lo.y)); line.addLine(to: CGPoint(x: k, y: hi.y))
            } else {
                line.move(to: CGPoint(x: lo.x, y: k)); line.addLine(to: CGPoint(x: hi.x, y: k))
            }
            inside.stroke(line, with: .color(Color(hex: 0x7A5230)), lineWidth: 1.6)
            k += 9
        }
        w.stroke(outline, with: .color(Color(hex: 0x6B4526)), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        // The side rails.
        var rails = Path()
        if alongX {
            for y in [lo.y + 2, hi.y - 2] { rails.move(to: CGPoint(x: lo.x, y: y)); rails.addLine(to: CGPoint(x: hi.x, y: y)) }
        } else {
            for x in [lo.x + 2, hi.x - 2] { rails.move(to: CGPoint(x: x, y: lo.y)); rails.addLine(to: CGPoint(x: x, y: hi.y)) }
        }
        w.stroke(rails, with: .color(Color(hex: 0xE9D6A6)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [3, 4]))
    }

    // MARK: Portals and tunnels

    private static func drawPortalEnd(_ w: inout GraphicsContext, _ at: Vec, radius: Double, color: Color, tunnel: Bool, time: Double) {
        let c = at.cg
        let r = CGFloat(radius)
        if tunnel {
            // A stone pipe mouth with a dark opening.
            w.fill(w.circle(CGPoint(x: c.x + 1.5, y: c.y + 4), r + 6), with: .color(.black.opacity(0.25)))
            w.fill(w.circle(c, r + 6), with: .color(Color(hex: 0xA99C74)))
            w.fill(w.circle(c, r + 3), with: .color(Color(hex: 0xD9CDA6)))
            w.fill(w.circle(c, r), with: .radialGradient(Gradient(colors: [.black.opacity(0.9), Color(hex: 0x2A2A2A)]), center: c, startRadius: 0, endRadius: r))
            w.stroke(w.circle(c, r), with: .color(color.opacity(0.9)), lineWidth: 2.5)
            return
        }
        // A swirling gateway: glow, spinning arcs and a dark centre.
        w.fill(w.circle(c, r + 9), with: .radialGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0)]), center: c, startRadius: r * 0.6, endRadius: r + 9))
        w.fill(w.circle(c, r), with: .radialGradient(Gradient(colors: [Color.black.opacity(0.85), color.opacity(0.85)]), center: c, startRadius: 0, endRadius: r))
        for k in 0..<3 {
            let a0 = time * 2.4 + Double(k) * 2.1
            var arc = Path()
            arc.addArc(center: c, radius: r * (0.45 + 0.17 * CGFloat(k)), startAngle: .radians(a0), endAngle: .radians(a0 + 1.7), clockwise: false)
            w.stroke(arc, with: .color(.white.opacity(0.85 - 0.18 * Double(k))), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
        w.stroke(w.circle(c, r), with: .color(color), lineWidth: 3)
    }

    // MARK: Moving walls

    /// `c` is clipped to the fairway: a wall that slides out of the side wall disappears into it
    /// instead of being drawn over the rough. The pivot of a pendulum sits on the rim, so it is
    /// drawn with `w`, unclipped.
    private static func drawMover(_ w: inout GraphicsContext, _ c: inout GraphicsContext, _ m: Mover, pal: Palette, time: Double) {
        // Its track, so the way it moves can be seen.
        switch m.motion {
        case .slide(let dir, let amplitude):
            // A sliding gate gets a groove to run in. A piston does not: its groove would stick
            // out ahead of the tip like a stem.
            if m.thickness <= 18 {
                let mid0 = (m.p0 + m.p1) * 0.5
                c.stroke(linePath(mid0 - dir * amplitude, mid0 + dir * amplitude), with: .color(.black.opacity(0.16)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        case .swing(let pivot, _):
            w.fill(w.circle(pivot.cg, 9), with: .color(Color(hex: 0x3B6FD6)))
            w.stroke(w.circle(pivot.cg, 9), with: .color(.black.opacity(0.25)), lineWidth: 1.5)
        }
        let e = m.ends(at: time)
        let bar = linePath(e.a, e.b)
        let t = CGFloat(m.thickness)
        c.stroke(bar.offsetBy(dx: 2, dy: 4), with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: t, lineCap: .round))
        c.stroke(bar, with: .color(Color(hex: 0x3B6FD6)), style: StrokeStyle(lineWidth: t, lineCap: .round))
        c.stroke(bar, with: .color(Color(hex: 0x8DB4F5)), style: StrokeStyle(lineWidth: t - 4, lineCap: .round))
        // The white stripes are drawn one by one, centred on the bar, not as a dash pattern: a dash
        // that ends right at the tip would flash as a hairline while the bar slides.
        let along = e.b - e.a
        let length = along.length
        if length > 14 {
            let unit = along / length
            let count = max(1, Int((length - 10) / 12))
            let first = (length - Double(count - 1) * 12) / 2
            var stripes = Path()
            for k in 0..<count {
                let mid = e.a + unit * (first + Double(k) * 12)
                stripes.move(to: (mid - unit * 2.5).cg)
                stripes.addLine(to: (mid + unit * 2.5).cg)
            }
            c.stroke(stripes, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: t - 6, lineCap: .butt))
        }
        if case .swing = m.motion {
            // A weight on the end of a pendulum.
            c.fill(c.circle(e.b.cg, t * 0.85), with: .color(Color(hex: 0x2F58B0)))
            c.stroke(c.circle(e.b.cg, t * 0.85), with: .color(.black.opacity(0.25)), lineWidth: 1.5)
        }
    }

    // MARK: Switches and doors

    private static func drawSwitch(_ w: inout GraphicsContext, _ s: FloorSwitch, color: Color, pressed: Bool) {
        let c = s.center.cg
        let r = CGFloat(s.radius)
        w.fill(w.circle(CGPoint(x: c.x, y: c.y + 3), r), with: .color(.black.opacity(0.22)))
        w.fill(w.circle(c, r), with: .color(Color(hex: 0xCFC9B6)))
        w.stroke(w.circle(c, r), with: .color(color), lineWidth: 3.5)
        w.fill(w.circle(c, r * (pressed ? 0.45 : 0.62)), with: .color(pressed ? color.opacity(0.45) : color))
        if !pressed { w.fill(w.circle(CGPoint(x: c.x - r * 0.2, y: c.y - r * 0.2), r * 0.18), with: .color(.white.opacity(0.7))) }
    }

    private static func drawDoor(_ w: inout GraphicsContext, _ d: Door, color: Color, open: Bool) {
        let p = path(d.outline)
        if open {
            w.stroke(p, with: .color(color.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [5, 5]))
            return
        }
        var inside = w
        inside.clip(to: p)
        w.fill(p.offsetBy(dx: 0, dy: 4), with: .color(.black.opacity(0.22)))
        w.fill(p, with: .color(color))
        let b = Poly.bounds(d.outline)
        var k = b.lo.x - (b.hi.y - b.lo.y)
        while k < b.hi.x {
            var stripe = Path()
            stripe.move(to: CGPoint(x: k, y: b.hi.y)); stripe.addLine(to: CGPoint(x: k + (b.hi.y - b.lo.y), y: b.lo.y))
            inside.stroke(stripe, with: .color(.white.opacity(0.35)), lineWidth: 4)
            k += 12
        }
        w.stroke(p, with: .color(.black.opacity(0.3)), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
    }

    // MARK: Walls with a trick

    private static func drawOneWay(_ w: inout GraphicsContext, _ g: OneWay, time: Double) {
        w.stroke(linePath(g.a, g.b).offsetBy(dx: 0, dy: 2), with: .color(.black.opacity(0.2)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        w.stroke(linePath(g.a, g.b), with: .color(Color(hex: 0x6D5BD0)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        // Arrows on the gate point the way a ball can go through.
        let dir = g.front.normalized
        let along = (g.b - g.a)
        let n = max(2, Int(along.length / 26))
        for k in 0..<n {
            let c = g.a + along * ((Double(k) + 0.5) / Double(n)) + dir * 9
            var chev = Path()
            chev.move(to: (c - dir * 4 + dir.perp * 5).cg)
            chev.addLine(to: (c + dir * 3).cg)
            chev.addLine(to: (c - dir * 4 - dir.perp * 5).cg)
            w.stroke(chev, with: .color(Color(hex: 0x6D5BD0).opacity(0.85)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
    }

    private static func drawBouncePad(_ w: inout GraphicsContext, _ b: BouncePad) {
        let bar = linePath(b.a, b.b)
        w.stroke(bar.offsetBy(dx: 1.5, dy: 4), with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: 11, lineCap: .round))
        w.stroke(bar, with: .color(Color(hex: 0xE5484D)), style: StrokeStyle(lineWidth: 11, lineCap: .round))
        w.stroke(bar, with: .color(Color(hex: 0xFF8A8A)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        w.stroke(bar, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .butt, dash: [2, 6]))
    }

    private static func drawBreakable(_ w: inout GraphicsContext, _ br: Breakable, pal: Palette) {
        let p = path(br.outline)
        var inside = w
        inside.clip(to: p)
        w.fill(p.offsetBy(dx: 0, dy: 4), with: .color(.black.opacity(0.22)))
        w.fill(p, with: .color(Color(hex: 0xE2AF8B)))
        let b = Poly.bounds(br.outline)
        // Brick lines and a crack.
        var y = b.lo.y + 7
        var row = 0
        while y < b.hi.y {
            var line = Path()
            line.move(to: CGPoint(x: b.lo.x, y: y)); line.addLine(to: CGPoint(x: b.hi.x, y: y))
            inside.stroke(line, with: .color(Color(hex: 0xA8755A).opacity(0.8)), lineWidth: 1.4)
            var x = b.lo.x + (row.isMultiple(of: 2) ? 0 : 11)
            while x < b.hi.x {
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: y)); tick.addLine(to: CGPoint(x: x, y: y + 7))
                inside.stroke(tick, with: .color(Color(hex: 0xA8755A).opacity(0.8)), lineWidth: 1.4)
                x += 22
            }
            y += 7; row += 1
        }
        var crack = Path()
        let mid = CGPoint(x: (b.lo.x + b.hi.x) / 2, y: (b.lo.y + b.hi.y) / 2)
        crack.move(to: CGPoint(x: mid.x - 8, y: b.lo.y)); crack.addLine(to: CGPoint(x: mid.x + 2, y: mid.y - 3))
        crack.addLine(to: CGPoint(x: mid.x - 4, y: mid.y + 3)); crack.addLine(to: CGPoint(x: mid.x + 6, y: b.hi.y))
        inside.stroke(crack, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        w.stroke(p, with: .color(Color(hex: 0x8E5A44)), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
    }
}
