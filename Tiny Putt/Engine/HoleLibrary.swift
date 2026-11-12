//
//  HoleLibrary.swift
//  Tiny Putt
//
//  The hand-made holes that open the game. Each one introduces a single idea. After these the
//  procedural generator (not written yet) takes over; until then the list repeats.
//

import Foundation

nonisolated enum HoleLibrary {
    static func hole(forLevel n: Int) -> Hole {
        all[(max(1, n) - 1) % all.count]
    }

    static let all: [Hole] = [
        straightaway(), dogleg(), sandTrap(), iceRink(), pinball(),
        windmill(), lavaLake(), magnet(), windy(), hills(),
    ]

    private static func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, radius: Double = 0) -> [Vec] {
        Poly.rounded(Poly.rect(x, y, w, h), radius: radius)
    }

    // 1. Aim and shoot.
    private static func straightaway() -> Hole {
        Hole(
            name: "The Straightaway",
            outline: box(235, 140, 130, 640, radius: 30),
            tee: Vec(300, 700), cup: Vec(300, 230), par: 2
        )
    }

    // 2. Walls can be used.
    private static func dogleg() -> Hole {
        Hole(
            name: "Dogleg",
            outline: Poly.rounded([
                Vec(190, 800), Vec(190, 200), Vec(490, 200), Vec(490, 340), Vec(330, 340), Vec(330, 800),
            ], radius: 26),
            tee: Vec(260, 715), cup: Vec(430, 270), par: 3
        )
    }

    // 3. Sand slows the ball.
    private static func sandTrap() -> Hole {
        Hole(
            name: "Sand Trap",
            theme: .desert,
            outline: box(170, 120, 260, 700, radius: 46),
            patches: [
                Patch(.sand, Poly.ellipse(Vec(262, 470), 85, 55)),
                Patch(.sand, Poly.ellipse(Vec(350, 330), 60, 40)),
            ],
            tee: Vec(300, 750), cup: Vec(300, 200), par: 2
        )
    }

    // 4. Ice keeps going.
    private static func iceRink() -> Hole {
        Hole(
            name: "Ice Rink",
            theme: .winter,
            outline: box(150, 130, 300, 660, radius: 50),
            blocks: [box(270, 470, 60, 60, radius: 8)],
            patches: [Patch(.ice, Poly.rounded(Poly.rect(150, 330, 300, 300), radius: 10))],
            tee: Vec(300, 730), cup: Vec(300, 215), par: 3
        )
    }

    // 5. Bumpers.
    private static func pinball() -> Hole {
        Hole(
            name: "Pinball",
            theme: .farm,
            outline: box(125, 130, 350, 680, radius: 70),
            bumpers: [
                Bumper(center: Vec(230, 360)),
                Bumper(center: Vec(370, 360)),
                Bumper(center: Vec(300, 500), radius: 26),
            ],
            tee: Vec(300, 740), cup: Vec(300, 215), par: 2
        )
    }

    // 6. Windmill and water.
    private static func windmill() -> Hole {
        Hole(
            name: "The Windmill",
            outline: Poly.rounded([
                Vec(205, 820), Vec(205, 560), Vec(170, 500), Vec(170, 200), Vec(200, 140),
                Vec(400, 140), Vec(430, 200), Vec(430, 500), Vec(395, 560), Vec(395, 820),
            ], radius: 28),
            patches: [
                Patch(.water, Poly.rounded(Poly.rect(188, 160, 62, 56), radius: 14)),
                Patch(.water, Poly.rounded(Poly.rect(350, 160, 62, 56), radius: 14)),
            ],
            windmills: [Windmill(center: Vec(300, 470), length: 100, speed: 1.0)],
            tee: Vec(300, 750), cup: Vec(300, 215), par: 3
        )
    }

    // 7. Lava is the floor.
    private static func lavaLake() -> Hole {
        Hole(
            name: "Hot Lava",
            theme: .desert,
            outline: box(150, 130, 300, 680, radius: 46),
            patches: [
                Patch(.lava, Poly.ellipse(Vec(225, 470), 90, 65)),
                Patch(.lava, Poly.ellipse(Vec(385, 380), 80, 60)),
            ],
            tee: Vec(300, 745), cup: Vec(300, 205), par: 3
        )
    }

    // 8. Magnets bend the path.
    private static func magnet() -> Hole {
        Hole(
            name: "Magnetic",
            theme: .farm,
            outline: box(135, 130, 330, 680, radius: 60),
            magnets: [Magnet(center: Vec(215, 440), radius: 150, strength: 800)],
            tee: Vec(300, 745), cup: Vec(300, 215), par: 3
        )
    }

    // 9. Wind pushes sideways.
    private static func windy() -> Hole {
        Hole(
            name: "Gusty",
            theme: .winter,
            outline: box(140, 130, 320, 680, radius: 56),
            patches: [Patch(.wind(Vec(260, 0)), Poly.rect(140, 300, 320, 260))],
            tee: Vec(260, 740), cup: Vec(300, 215), par: 3
        )
    }

    // 10. Hills roll the ball.
    private static func hills() -> Hole {
        Hole(
            name: "Rolling Hills",
            outline: box(130, 130, 340, 680, radius: 60),
            blocks: [box(285, 380, 30, 120, radius: 8)],
            patches: [
                Patch(.slope(Vec(170, 0)), Poly.rounded(Poly.rect(130, 560, 340, 130), radius: 12)),
                Patch(.slope(Vec(-170, 0)), Poly.rounded(Poly.rect(130, 250, 340, 110), radius: 12)),
            ],
            tee: Vec(300, 750), cup: Vec(300, 200), par: 3
        )
    }
}
