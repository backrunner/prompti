import Network
import Observation
import UIKit

@MainActor
@Observable
final class InventoryConditions {
    private(set) var hasNetwork = false
    private(set) var usesWiFi = false
    private(set) var isConstrained = false
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.hasNetwork = path.status == .satisfied
                self?.usesWiFi = path.usesInterfaceType(.wifi)
                self?.isConstrained = path.isConstrained
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.prompti.inventory-network"))
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    deinit { monitor.cancel() }

    func allowsPreparation(wifiOnly: Bool, onDevice: Bool) -> Bool {
        let battery = UIDevice.current.batteryLevel
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled,
              battery < 0 || battery > 0.2 || UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full else { return false }
        return onDevice || (hasNetwork && !isConstrained && (!wifiOnly || usesWiFi))
    }
}
