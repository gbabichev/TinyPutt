//
//  ScreenInsets.swift
//  Tiny Putt
//
//  Screens centre their content on the whole display, not on the safe area, so nothing looks
//  off-centre next to a big gutter (the iPhone Duo has a wide one beside the camera). The real
//  safe-area insets are passed down so that corner buttons can still keep clear of the gutter.
//  This is for landscape. In portrait everything simply stays inside the safe area.
//

import SwiftUI

extension EnvironmentValues {
    /// The safe-area insets of the display, as reported before the screens ignored them sideways.
    @Entry var screenInsets = EdgeInsets()
}

/// Lays `content` out across the full width of the display and hands it the safe-area insets.
struct FullWidth<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            content
                .environment(\.screenInsets, EdgeInsets(
                    top: geo.safeAreaInsets.top,
                    leading: landscape ? geo.safeAreaInsets.leading : 0,
                    bottom: geo.safeAreaInsets.bottom,
                    trailing: landscape ? geo.safeAreaInsets.trailing : 0))
                .ignoresSafeArea(.container, edges: landscape ? .horizontal : [])
        }
    }
}
