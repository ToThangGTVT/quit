import Foundation
import Observation

/// Trạng thái UI dùng chung giữa cửa sổ SwiftUI và menu bar của macOS.
/// Kiểu đồ thị CPU, tương ứng "Change graph to" của Task Manager.
enum PerfGraphMode: String {
    case overall, logicalProcessors
}

@Observable
class TaskManagerState {
    var tab: TMTab = .processes
    var perfResource: PerfResource = .cpu
    var perfGraphMode: PerfGraphMode = .overall
    var showKernelTimes = false
    var perfSummaryView = false
    var collapsedGroups: Set<String> = []

    var procSelection: Set<Int32> = []
    var detailsSelection: Set<Int32> = []
    var usersSelection: Set<Int32> = []
    var startupSelection: Set<String> = []
    var servicesSelection: Set<String> = []

    /// PID đang chọn ở tab hiện tại (dùng cho "Kết thúc tác vụ" ở menu và chân cửa sổ).
    var selectedPids: Set<Int32> {
        switch tab {
        case .processes: return procSelection
        case .details:   return detailsSelection
        case .users:     return usersSelection
        default:         return []
        }
    }

    func clearSelectedPids() {
        switch tab {
        case .processes: procSelection.removeAll()
        case .details:   detailsSelection.removeAll()
        case .users:     usersSelection.removeAll()
        default:         break
        }
    }
}
