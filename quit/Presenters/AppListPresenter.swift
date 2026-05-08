import SwiftUI
import Observation

@Observable
class AppListPresenter: AppMonitorInteractorOutput {
    private var rawEntities: [AppEntity] = []
    var systemStats = SystemStats(memoryUsagePercentage: 0, memoryPressure: 0, netRxKBs: 0, netTxKBs: 0)
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
        netMap: [Int32: (rx: Double, tx: Double)],
        stats: SystemStats
    ) {
        rawEntities = apps.map { app in
            let pid = app.processIdentifier
            return AppEntity(
                id: pid,
                name: app.localizedName ?? "Unknown",
                memory: memoryMap[pid] ?? 0,
                cpu: cpuMap[pid] ?? 0,
                netRxKBs: netMap[pid]?.rx ?? 0,
                netTxKBs: netMap[pid]?.tx ?? 0,
                isRegular: app.activationPolicy == .regular,
                runningApp: app
            )
        }
        systemStats = stats
    }
}
