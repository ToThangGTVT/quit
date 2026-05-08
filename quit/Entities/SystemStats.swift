import SwiftUI

struct SystemStats {
    let memoryUsagePercentage: Double
    let memoryPressure: Int
    let netRxKBs: Double  // system-wide download KB/s
    let netTxKBs: Double  // system-wide upload KB/s

    var pressureText: String {
        if memoryPressure == 1 { return "Thấp" }
        if memoryPressure == 2 { return "Vừa" }
        if memoryPressure == 4 { return "Cao" }
        if memoryUsagePercentage < 50 { return "Thấp" }
        if memoryUsagePercentage < 80 { return "Vừa" }
        return "Cao"
    }

    var pressureColor: Color {
        if memoryPressure == 1 { return .green }
        if memoryPressure == 2 { return .orange }
        if memoryPressure == 4 { return .red }
        if memoryUsagePercentage < 50 { return .green }
        if memoryUsagePercentage < 80 { return .orange }
        return .red
    }
}
