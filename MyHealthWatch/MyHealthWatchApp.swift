import SwiftUI

@main
struct MyHealthWatchApp: App {
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
                .onOpenURL { router.handle(url: $0) }
        }
    }
}
