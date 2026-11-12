//
//  Scenery.swift
//  Tiny Putt
//
//  The decoration around a hole: bushes, rocks, pumpkins and so on, scattered over a grid with
//  a stable hash so a hole always looks the same, on any screen size.
//

import SwiftUI

struct SceneryItem {
    enum Kind { case bush, rock, flower, tuft, pumpkin, hay, cactus, pine, mound }
    var kind: Kind
    var pos: CGPoint
    var size: CGFloat
    var variant: Double
}

enum Scenery {
    private static let cell = 58.0

    private static func hash(_ a: Int, _ b: Int, _ salt: Int) -> Double {
        var h = UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(b)) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= UInt64(bitPattern: Int64(salt)) &* 0x1656_67B1_9E37_79F9
        h ^= h >> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 32
        return Double(h >> 11) / Double(1 << 53)
    }

    /// The decoration that falls in `rect` (world units), kept clear of the playing area.
    static func make(in rect: CGRect, avoiding outline: [Vec], theme: ThemeID) -> [SceneryItem] {
        var items: [SceneryItem] = []
        let x0 = Int(floor(rect.minX / cell)), x1 = Int(ceil(rect.maxX / cell))
        let y0 = Int(floor(rect.minY / cell)), y1 = Int(ceil(rect.maxY / cell))
        guard x1 >= x0, y1 >= y0 else { return [] }
        for ix in x0...x1 {
            for iy in y0...y1 {
                guard hash(ix, iy, 1) < 0.62 else { continue }
                let p = Vec((Double(ix) + hash(ix, iy, 2)) * cell, (Double(iy) + hash(ix, iy, 3)) * cell)
                if !outline.isEmpty {
                    if Poly.contains(outline, p) { continue }
                    var near = false
                    for i in 0..<outline.count {
                        let c = Poly.closestPoint(outline[i], outline[(i + 1) % outline.count], to: p)
                        if c.distance(to: p) < 40 { near = true; break }
                    }
                    if near { continue }
                }
                let roll = hash(ix, iy, 4)
                let variant = hash(ix, iy, 5)
                let size = CGFloat(11 + 11 * hash(ix, iy, 6))
                let kind: SceneryItem.Kind
                switch theme {
                case .meadow: kind = roll < 0.40 ? .bush : roll < 0.55 ? .rock : roll < 0.80 ? .flower : .tuft
                case .farm: kind = roll < 0.22 ? .pumpkin : roll < 0.38 ? .hay : roll < 0.46 ? .rock : .tuft
                case .desert: kind = roll < 0.28 ? .cactus : roll < 0.55 ? .rock : .tuft
                case .winter: kind = roll < 0.42 ? .pine : roll < 0.68 ? .mound : roll < 0.82 ? .rock : .tuft
                }
                items.append(SceneryItem(kind: kind, pos: p.cg, size: size, variant: variant))
            }
        }
        return items
    }
}

// MARK: - Drawing

extension GraphicsContext {
    func star(center: CGPoint, outer: CGFloat, inner: CGFloat, points: Int, rotation: CGFloat = 0) -> Path {
        var path = Path()
        for i in 0..<(points * 2) {
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = rotation + CGFloat(i) * .pi / CGFloat(points)
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    func drawScenery(_ item: SceneryItem, palette: Palette, theme: ThemeID) {
        let c = item.pos
        let s = item.size
        let shadow = Color.black.opacity(0.18)
        switch item.kind {
        case .bush:
            let rot = CGFloat(item.variant) * 3
            fill(star(center: CGPoint(x: c.x + 2, y: c.y + 3), outer: s, inner: s * 0.72, points: 9, rotation: rot), with: .color(shadow))
            fill(star(center: c, outer: s, inner: s * 0.72, points: 9, rotation: rot), with: .color(palette.plantDark))
            fill(star(center: c, outer: s * 0.68, inner: s * 0.5, points: 9, rotation: rot + 0.3), with: .color(palette.plantLight))
            fill(circle(c, s * 0.26), with: .color(palette.plantLight.opacity(0.6)))
        case .pine:
            fill(circle(CGPoint(x: c.x + 2, y: c.y + 3), s), with: .color(shadow))
            fill(star(center: c, outer: s, inner: s * 0.7, points: 8, rotation: CGFloat(item.variant)), with: .color(palette.plantDark))
            fill(star(center: c, outer: s * 0.66, inner: s * 0.46, points: 8, rotation: CGFloat(item.variant) + 0.4), with: .color(palette.plantLight))
            fill(circle(c, s * 0.28), with: .color(.white.opacity(0.85)))
        case .rock:
            var p = Path()
            let n = 7
            for i in 0..<n {
                let a = CGFloat(i) / CGFloat(n) * 2 * .pi
                let r = s * 0.55 * CGFloat(0.8 + 0.35 * sin(Double(i) * 12.9898 + item.variant * 78.233).magnitude)
                let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            fill(p.offsetBy(dx: 1.5, dy: 2.5), with: .color(shadow))
            fill(p, with: .color(palette.rock))
            fill(circle(CGPoint(x: c.x - s * 0.12, y: c.y - s * 0.14), s * 0.2), with: .color(.white.opacity(0.35)))
        case .flower:
            let colors: [Color] = [.white, Color(hex: 0xFFE27A), Color(hex: 0xF7A8C8)]
            let col = colors[Int(item.variant * 3) % 3]
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2 + CGFloat(item.variant) * 6
                fill(circle(CGPoint(x: c.x + cos(a) * 3, y: c.y + sin(a) * 3), 2.2), with: .color(col))
            }
            fill(circle(c, 1.6), with: .color(Color(hex: 0xF2B63C)))
        case .tuft:
            let col = palette.roughMark
            for i in -1...1 {
                var p = Path()
                let base = CGPoint(x: c.x + CGFloat(i) * 4, y: c.y)
                p.move(to: base)
                p.addLine(to: CGPoint(x: base.x + CGFloat(i) * 2, y: base.y - s * 0.55))
                stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        case .pumpkin:
            let body = CGRect(x: c.x - s * 0.8, y: c.y - s * 0.62, width: s * 1.6, height: s * 1.24)
            fill(Path(ellipseIn: body.offsetBy(dx: 2, dy: 3)), with: .color(shadow))
            fill(Path(ellipseIn: body), with: .color(palette.plantDark))
            for k in [-0.4, 0.0, 0.4] {
                var p = Path()
                p.move(to: CGPoint(x: c.x + s * k, y: c.y - s * 0.6))
                p.addQuadCurve(to: CGPoint(x: c.x + s * k, y: c.y + s * 0.6), control: CGPoint(x: c.x + s * k * 1.7, y: c.y))
                stroke(p, with: .color(palette.plantLight), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            fill(Path(roundedRect: CGRect(x: c.x - 1.5, y: c.y - s * 0.78, width: 3, height: s * 0.34), cornerRadius: 1.5), with: .color(Color(hex: 0x4E8A3A)))
        case .hay:
            fill(circle(CGPoint(x: c.x + 2, y: c.y + 3), s * 0.9), with: .color(shadow))
            fill(circle(c, s * 0.9), with: .color(Color(hex: 0xE6C46F)))
            for k in [0.65, 0.4, 0.18] {
                stroke(circle(c, s * 0.9 * k), with: .color(Color(hex: 0xB8963F)), lineWidth: 1.4)
            }
        case .cactus:
            fill(star(center: CGPoint(x: c.x + 2, y: c.y + 3), outer: s * 0.7, inner: s * 0.5, points: 6), with: .color(shadow))
            fill(star(center: c, outer: s * 0.7, inner: s * 0.5, points: 6, rotation: CGFloat(item.variant)), with: .color(palette.plantDark))
            fill(circle(c, s * 0.34), with: .color(palette.plantLight))
            fill(circle(c, s * 0.12), with: .color(Color(hex: 0xF28AB0)))
        case .mound:
            fill(circle(CGPoint(x: c.x + 2, y: c.y + 3), s * 0.85), with: .color(Color(hex: 0x9DB4C4).opacity(0.5)))
            fill(circle(c, s * 0.85), with: .color(.white))
            stroke(circle(c, s * 0.85), with: .color(Color(hex: 0xC9D8E2)), lineWidth: 1.5)
        }
    }
}
