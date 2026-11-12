//
//  Sheet.swift
//  HoleChecker
//
//  Draws a contact sheet of holes (for a quick look at what the generator made).
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func writeSheet(_ holes: [Hole], to path: String, columns: Int = 8, cell: Int = 180, paths shotPaths: [[Vec]] = []) {
    let rows = (holes.count + columns - 1) / columns
    let width = columns * cell, height = rows * cell
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

    func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
    }
    func poly(_ pts: [Vec], _ t: (Vec) -> CGPoint) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map(t))
        p.closeSubpath()
        return p
    }

    for (i, h) in holes.enumerated() {
        let col = i % columns, row = i / columns
        let rough: UInt32 = [0x6A9B52, 0xD4B25E, 0xE2C58E, 0xE6EEF3][h.theme.rawValue]
        let x0 = CGFloat(col * cell), y0 = CGFloat(height - (row + 1) * cell)
        ctx.setFillColor(color(rough))
        ctx.fill(CGRect(x: x0, y: y0, width: CGFloat(cell), height: CGFloat(cell)))
        let scale = CGFloat(cell - 12) / CGFloat(max(h.size.x, h.size.y))
        let ox = x0 + (CGFloat(cell) - CGFloat(h.size.x) * scale) / 2
        let oy = y0 + (CGFloat(cell) - CGFloat(h.size.y) * scale) / 2
        // World y points down; the bitmap's y points up.
        let t: (Vec) -> CGPoint = { CGPoint(x: ox + CGFloat($0.x) * scale, y: oy + (CGFloat(h.size.y) - CGFloat($0.y)) * scale) }

        ctx.saveGState()
        ctx.clip(to: CGRect(x: x0, y: y0, width: CGFloat(cell), height: CGFloat(cell)))
        let outline = poly(h.outline, t)
        ctx.setStrokeColor(color(0xF6EDCB)); ctx.setLineWidth(7 * scale * 2.2)
        ctx.addPath(outline); ctx.strokePath()
        ctx.setFillColor(color(0x4AAA66)); ctx.addPath(outline); ctx.fillPath()

        ctx.saveGState()
        ctx.addPath(outline); ctx.clip()
        for p in h.patches {
            let c: UInt32
            switch p.kind {
            case .sand: c = 0xEBD9A0
            case .mud: c = 0x7C5B3A
            case .ice: c = 0xDDF2FB
            case .water: c = 0x4FA3E0
            case .lava: c = 0xD2431F
            case .slope: c = 0xB9E5C2
            case .wind: c = 0xFFFFFF
            }
            ctx.setFillColor(color(c, { if case .wind = p.kind { return 0.45 }; return 1 }()))
            ctx.addPath(poly(p.outline, t)); ctx.fillPath()
        }
        for b in h.blocks {
            ctx.setFillColor(color(0xF6EDCB)); ctx.addPath(poly(b, t)); ctx.fillPath()
        }
        ctx.restoreGState()

        for b in h.bumpers {
            let c = t(b.center), r = CGFloat(b.radius) * scale
            ctx.setFillColor(color(0xE5484D)); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        for b in h.bowls {
            let c = t(b.center), r = CGFloat(b.radius) * scale
            ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineWidth(1.2)
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        for m in h.magnets {
            let c = t(m.center), r = CGFloat(m.radius) * scale * 0.5
            ctx.setStrokeColor(color(m.strength > 0 ? 0xA855F7 : 0xF97316)); ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        for w in h.windmills {
            let c = t(w.center)
            ctx.setStrokeColor(color(0xB89C63)); ctx.setLineWidth(2.5)
            for k in 0..<w.blades {
                let tip = t(w.tip(of: k, at: 0))
                ctx.move(to: c); ctx.addLine(to: tip)
            }
            ctx.strokePath()
            ctx.setFillColor(color(0xE5484D)); ctx.fillEllipse(in: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
        }
        let palette: [UInt32] = [0xFFFFFF, 0xFFE066, 0x7DD3FC, 0xF9A8D4, 0xC4B5FD, 0xFDBA74]
        for (k, route) in shotPaths.enumerated() where holes.count == 1 {
            ctx.setStrokeColor(color(0x111111, 0.6)); ctx.setLineWidth(5)
            ctx.addLines(between: route.map(t)); ctx.strokePath()
            ctx.setStrokeColor(color(palette[k % palette.count])); ctx.setLineWidth(3)
            ctx.addLines(between: route.map(t)); ctx.strokePath()
            if let end = route.last { let e = t(end); ctx.setFillColor(color(palette[k % palette.count])); ctx.fillEllipse(in: CGRect(x: e.x - 5, y: e.y - 5, width: 10, height: 10)) }
        }
        let cup = t(h.cup), tee = t(h.tee)
        ctx.setFillColor(color(0x111111)); ctx.fillEllipse(in: CGRect(x: cup.x - 4, y: cup.y - 4, width: 8, height: 8))
        ctx.setFillColor(color(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: tee.x - 3.5, y: tee.y - 3.5, width: 7, height: 7))
        ctx.restoreGState()
        // Cell border.
        ctx.setStrokeColor(color(0x000000, 0.5)); ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: x0, y: y0, width: CGFloat(cell), height: CGFloat(cell)))
    }

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
