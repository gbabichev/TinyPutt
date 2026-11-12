//
//  Palette.swift
//  Tiny Putt
//

import SwiftUI

/// The colours of one world.
struct Palette {
    var rough: Color
    var roughMark: Color
    var fairway: Color
    var rim: Color
    var rimShade: Color
    var plantDark: Color
    var plantLight: Color
    var rock: Color
    var sand: Color
    var sandDot: Color
    var isDark = false

    // The same in every world.
    let water = Color(hex: 0x4FA3E0)
    let waterLine = Color(hex: 0xBFE2F8)
    let waterDeep = Color(hex: 0x2A78BC)
    let waterShallow = Color(hex: 0x7CCBF2)
    let stone = Color(hex: 0xD9CDA6)
    let stoneShade = Color(hex: 0xA99C74)
    let waterEdge = Color(hex: 0x2F7FBF)
    let lava = Color(hex: 0xD2431F)
    let lavaGlow = Color(hex: 0xFFB03A)
    let lavaHot = Color(hex: 0xFFE27A)
    let lavaDeep = Color(hex: 0x9E2410)
    let crust = Color(hex: 0x3B1A14)
    let lavaEdge = Color(hex: 0x7A1E10)
    let ice = Color(hex: 0xDDF2FB)
    let iceLine = Color(hex: 0xFFFFFF)
    let iceEdge = Color(hex: 0xA9D5EA)
    let mud = Color(hex: 0x7C5B3A)
    let bumper = Color(hex: 0xE5484D)
    let wood = Color(hex: 0xE9D6A6)
    let woodEdge = Color(hex: 0xB89C63)
    let flag = Color(hex: 0xE5484D)
}

extension ThemeID {
    var palette: Palette {
        switch self {
        case .meadow:
            Palette(rough: Color(hex: 0x6A9B52), roughMark: Color(hex: 0x5A8A45), fairway: Color(hex: 0x4AAA66),
                    rim: Color(hex: 0xF6EDCB), rimShade: Color(hex: 0xCDBF94),
                    plantDark: Color(hex: 0x2F7D4F), plantLight: Color(hex: 0x41A062), rock: Color(hex: 0xA6AAA6),
                    sand: Color(hex: 0xEBD9A0), sandDot: Color(hex: 0xCDB677))
        case .farm:
            Palette(rough: Color(hex: 0xD4B25E), roughMark: Color(hex: 0xB8963F), fairway: Color(hex: 0x4AAA66),
                    rim: Color(hex: 0xFBF1D2), rimShade: Color(hex: 0xD2BF8C),
                    plantDark: Color(hex: 0xE0771A), plantLight: Color(hex: 0xF29A3C), rock: Color(hex: 0xB5A58A),
                    sand: Color(hex: 0xEBD9A0), sandDot: Color(hex: 0xCDB677))
        case .desert:
            Palette(rough: Color(hex: 0xE2C58E), roughMark: Color(hex: 0xC9A66B), fairway: Color(hex: 0x6DB56B),
                    rim: Color(hex: 0xFFF3D6), rimShade: Color(hex: 0xD8C196),
                    plantDark: Color(hex: 0x3F8F57), plantLight: Color(hex: 0x5CB070), rock: Color(hex: 0xB59D7B),
                    sand: Color(hex: 0xF6E8BE), sandDot: Color(hex: 0xD9C48C))
        case .winter:
            Palette(rough: Color(hex: 0xE6EEF3), roughMark: Color(hex: 0xC9D8E2), fairway: Color(hex: 0x58AF8B),
                    rim: Color(hex: 0xFFFFFF), rimShade: Color(hex: 0xBFD0DB),
                    plantDark: Color(hex: 0x2F6B55), plantLight: Color(hex: 0x468B6E), rock: Color(hex: 0x9AA6AE),
                    sand: Color(hex: 0xEBD9A0), sandDot: Color(hex: 0xCDB677))
        }
    }
}
