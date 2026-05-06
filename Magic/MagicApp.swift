//
//  MagicApp.swift
//  Magic
//
//  Created by CoderWan on 2026/2/25.
//

import SwiftUI

@main
struct MagicApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

// MARK: - Demo

struct DemoView: View {
    @State private var value: Double = 50
    @State var selectedItem: PicCameraMode = .photo
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            PicSegmentedControl(items: [.photo, .portrait], selectedItem: $selectedItem)
        }
    }
}

#Preview {
    DemoView()
}

