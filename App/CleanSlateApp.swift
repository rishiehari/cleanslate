import SwiftUI

@main
struct CleanSlateApp: App {
    @StateObject private var model = CleaningViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(model)
                .tint(Color(red: 0.12, green: 0.55, blue: 0.42))
        }
    }
}
