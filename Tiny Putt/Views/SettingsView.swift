//
//  SettingsView.swift
//  Tiny Putt
//

import SwiftUI

struct SettingsView: View {
    @Bindable var game: GolfGame
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        SheetFrame(title: "Settings", onDone: { dismiss() }) {
            toggleRow("Sound", isOn: $game.isSoundOn)
            // The Mac never buzzes the trackpad, so the switch only exists on iPhone and iPad.
            if Haptics.isAvailable {
                toggleRow("Haptics", isOn: $game.isHapticsOn)
            }
            Button("Reset all progress") { confirmingReset = true }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 12)
        }
        .confirmationDialog("Erase every player and start again?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { game.resetEverything() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Ink.dark)
        }
        .tint(Ink.green)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.55)))
    }
}
