import SwiftUI

struct RootView: View {
    var body: some View {
        VStack {
            Text("Welcome to GarageHUD!")
                .font(.largeTitle)
                .padding()
            Text("Your app is running.")
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
    }
}
