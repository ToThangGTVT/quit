import SwiftUI
import Observation

@Observable
class AppListPresenter: AppMonitorInteractorOutput {
    private var rawEntities: [AppEntity] = []
    var systemStats = SystemStats(memoryUsagePercentage: 0, memoryPressure: 0)
    var sortOrder = [KeyPathComparator(\AppEntity.memory, order: .reverse)]

    var appEntities: [AppEntity] { rawEntities.sorted(using: sortOrder) }

    private let interactor: AppMonitorInteractor

    init(interactor: AppMonitorInteractor = AppMonitorInteractor()) {
        self.interactor = interactor
        interactor.output = self
        interactor.start()
    }

    func refresh() { interactor.refresh() }

    func forceQuit(_ entity: AppEntity) {
        entity.runningApp.forceTerminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.interactor.refresh() }
    }

    func interactorDidUpdate(
        apps: [NSRunningApplication],
        memoryMap: [Int32: Double],
        cpuMap: [Int32: Double],
        stats: SystemStats
    ) {
        rawEntities = apps.map { app in
            AppEntity(
                id: app.processIdentifier,
                name: app.localizedName ?? "Unknown",
                memory: memoryMap[app.processIdentifier] ?? 0,
                cpu: cpuMap[app.processIdentifier] ?? 0,
                isRegular: app.activationPolicy == .regular,
                runningApp: app
            )
        }
        systemStats = stats
    }
}
