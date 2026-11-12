//
//  Tiny_PuttApp.swift
//  Tiny Putt
//
//  Created by George Babichev on 11/11/26.
//

import SwiftUI

@main
struct Tiny_PuttApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 700)
        #endif
    }
}
