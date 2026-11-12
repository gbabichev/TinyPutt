//
//  Geometry.swift
//  Tiny Putt
//
//  Plain geometry for the engine. Nothing here knows about SwiftUI, so the same code can be
//  compiled into a command-line hole checker.
//

import Foundation
import CoreGraphics

nonisolated struct Vec: Hashable, Sendable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    static let zero = Vec(0, 0)

    static func + (a: Vec, b: Vec) -> Vec { Vec(a.x + b.x, a.y + b.y) }
    static func - (a: Vec, b: Vec) -> Vec { Vec(a.x - b.x, a.y - b.y) }
    static func * (a: Vec, k: Double) -> Vec { Vec(a.x * k, a.y * k) }
    static func / (a: Vec, k: Double) -> Vec { Vec(a.x / k, a.y / k) }
    static prefix func - (a: Vec) -> Vec { Vec(-a.x, -a.y) }
    static func += (a: inout Vec, b: Vec) { a = a + b }
    static func -= (a: inout Vec, b: Vec) { a = a - b }

    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: Vec { let l = length; return l > 1e-12 ? self / l : .zero }
    /// Turned a quarter turn (x right, y down: clockwise on screen).
    var perp: Vec { Vec(-y, x) }
    var cg: CGPoint { CGPoint(x: x, y: y) }

    func dot(_ o: Vec) -> Double { x * o.x + y * o.y }
    func distance(to o: Vec) -> Double { (self - o).length }
}

nonisolated enum Poly {
    /// Whether a point is inside a closed polygon (even-odd rule).
    static func contains(_ poly: [Vec], _ p: Vec) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// The point on segment a-b nearest to p.
    static func closestPoint(_ a: Vec, _ b: Vec, to p: Vec) -> Vec {
        let ab = b - a
        let l2 = ab.dot(ab)
        if l2 < 1e-12 { return a }
        let t = max(0, min(1, (p - a).dot(ab) / l2))
        return a + ab * t
    }

    static func bounds(_ pts: [Vec]) -> (lo: Vec, hi: Vec) {
        var lo = Vec(.infinity, .infinity), hi = Vec(-.infinity, -.infinity)
        for p in pts {
            lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y)
            hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y)
        }
        return (lo, hi)
    }

    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [Vec] {
        [Vec(x, y), Vec(x + w, y), Vec(x + w, y + h), Vec(x, y + h)]
    }

    static func ellipse(_ c: Vec, _ rx: Double, _ ry: Double, steps: Int = 48) -> [Vec] {
        (0..<steps).map { i in
            let a = Double(i) / Double(steps) * 2 * .pi
            return Vec(c.x + cos(a) * rx, c.y + sin(a) * ry)
        }
    }

    /// Rounds every corner of a polygon. Both the physics and the drawing use the result, so a
    /// ball bounces off exactly what the player sees.
    static func rounded(_ pts: [Vec], radius: Double, steps: Int = 6) -> [Vec] {
        guard radius > 0, pts.count >= 3 else { return pts }
        var out: [Vec] = []
        let n = pts.count
        for i in 0..<n {
            let v = pts[i], prev = pts[(i + n - 1) % n], next = pts[(i + 1) % n]
            let d1 = prev - v, d2 = next - v
            let r = min(radius, d1.length / 2, d2.length / 2)
            let p1 = v + d1.normalized * r
            let p2 = v + d2.normalized * r
            for s in 0...steps {
                let t = Double(s) / Double(steps)
                let a = p1 * ((1 - t) * (1 - t)) + v * (2 * (1 - t) * t) + p2 * (t * t)
                out.append(a)
            }
        }
        return out
    }
}
