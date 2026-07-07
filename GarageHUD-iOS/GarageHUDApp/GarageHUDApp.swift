import SwiftUI
// GarageHUDKit sources are compiled directly into this target (see project.pbxproj
// synchronized group), so RootView is in-module — no import needed.

@main
struct GarageHUDApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
