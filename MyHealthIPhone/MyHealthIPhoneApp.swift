import SwiftUI

/// iPhone entry point. This build is designed for sideloading (Sideloadly):
/// it uses no HealthKit permission and no entitlements — all insights come
/// from the Apple Health export you import.
@main
struct MyHealthIPhoneApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var router: AppRouter

    init() {
        let router = AppRouter()
        _router = StateObject(wrappedValue: router)
        AppRouter.shared = router
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(router)
                .preferredColorScheme(.dark)
        }
    }
}
