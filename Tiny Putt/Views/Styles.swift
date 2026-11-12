//
//  Styles.swift
//  Tiny Putt
//

import SwiftUI

enum Ink {
    static let dark = Color(hex: 0x1F3A2D)
    static let cream = Color(hex: 0xF6EDCB)
    static let green = Color(hex: 0x3E9A5B)
}

/// A rounded button: cream by default, green when it is the main action.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(prominent ? Color.white : Ink.dark)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .frame(maxWidth: 320)
            .background(Capsule().fill(prominent ? Ink.green : Ink.cream))
            .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The small round buttons over the course.
struct RoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(Ink.dark)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Ink.cream))
            .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct BallDot: View {
    let color: BallColor
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                Circle().fill(.white.opacity(0.6)).frame(width: size * 0.3, height: size * 0.3)
                    .offset(x: size * 0.2, y: size * 0.2)
            }
    }
}

/// A card on top of the game.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 14) { content }
            .padding(24)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Ink.cream))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.black.opacity(0.1), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
            .padding(24)
    }
}
