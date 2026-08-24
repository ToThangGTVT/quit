import SwiftUI
import ServiceManagement

@main
struct QuitApp: App {
    @State private var presenter = AppListPresenter()
    @State private var router = AppRouter()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        try? SMAppService.mainApp.register()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(presenter: presenter, router: router)
        } label: {
            MenuBarLabel(presenter: presenter)
                .task {
                    // Mở lại ứng dụng (double-click trong Finder) sẽ hiện Trình quản lý Tác vụ.
                    AppDelegate.onReopen = { [presenter, router] in
                        router.openDetailWindow(presenter: presenter)
                    }
                }
        }
        .menuBarExtraStyle(.window)
        .commands {
            TaskManagerCommands(presenter: presenter, router: router, state: router.state)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var onReopen: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppDelegate.onReopen?()
        return true
    }
}
