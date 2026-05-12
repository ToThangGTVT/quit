import SwiftUI
import Observation

@Observable
class AppListPresenter: AppMonitorInteractorOutput {
    private var rawEntities: [AppEntity] = []
    var systemStats = SystemStats(memoryUsagePercentage: 0, memoryPressure: 0, netRxKBs: 0, netTxKBs: 0)
    var sortOrder = [KeyPathComparator(\AppEntity.memory, order: .reverse)]

    var appEntities: [AppEntity] { rawEntities.sorted(using: sortOrder) }
    var guiAppEntities: [AppEntity] { appEntities.filter { $0.isGUIApp } }

    private let interactor: AppMonitorInteractor

    init(interactor: AppMonitorInteractor = AppMonitorInteractor()) {
        self.interactor = interactor
        interactor.output = self
        interactor.start()
    }

    func refresh() { interactor.refresh() }

    func forceQuit(_ entity: AppEntity) {
        if let app = entity.runningApp {
            app.forceTerminate()
        } else {
            kill(entity.id, SIGKILL)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.interactor.refresh() }
    }

    func interactorDidUpdate(entities: [AppEntity], stats: SystemStats) {
        rawEntities = entities
        systemStats = stats
    }
}
