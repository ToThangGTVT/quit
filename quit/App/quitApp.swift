import SwiftUI
import ServiceManagement

@main
struct QuitApp: App {
    @State private var presenter = AppListPresenter()
    @State private var router = AppRouter()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        try? SMAppService.mainApp.register()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(presenter: presenter, router: router)
        } label: {
            MenuBarLabel(presenter: presenter)
        }
        .menuBarExtraStyle(.window)
    }
}
