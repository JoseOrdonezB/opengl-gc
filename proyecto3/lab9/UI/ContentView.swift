//
//  ContentView.swift
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MetalView()
            .ignoresSafeArea()
            .onAppear {
                BGMPlayer.shared.play()
            }
            .onDisappear {
                BGMPlayer.shared.stop()
            }
    }
}
