import Foundation
import CoreBluetooth
import Combine

/// Manages a dual-role Core Bluetooth stack:
/// - CBPeripheralManager: advertises own device UUID as a BLE service UUID so other Vicinity
///   devices running CBCentralManager can find this device in background.
/// - CBCentralManager: scans for service UUIDs of peers with pending scheduled messages.
///   When found, the app is already alive so MultipeerConnectivity can complete the handshake.
///
/// Background modes required (set in Xcode target capabilities):
///   - Uses Bluetooth LE accessories (bluetooth-central)
///   - Acts as a Bluetooth LE accessory (bluetooth-peripheral)
final class ProximityBluetoothService: NSObject, ObservableObject {

    // MARK: - Constants

    private static let centralRestoreIdentifier = "com.vicinity.proximity-central"
    private static let peripheralRestoreIdentifier = "com.vicinity.proximity-peripheral"

    // MARK: - State

    /// Peer UUIDs to scan for (updated whenever scheduled messages change).
    @Published private(set) var scanTargetUUIDs: [String] = []

    /// Called on main thread when a target peer's BLE advertisement is detected.
    var onPeerDetected: ((String) -> Void)?

    // MARK: - BLE managers

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!

    /// The device's own UUID (used as BLE service UUID for advertisement).
    private let deviceUUID: String

    // MARK: - Init

    init(deviceUUID: String) {
        self.deviceUUID = deviceUUID
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreIdentifier]
        )
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.peripheralRestoreIdentifier]
        )
    }

    // MARK: - Public API

    /// Update the set of peer UUIDs to scan for. Call whenever scheduled messages are
    /// created or cancelled so the scanner targets stay in sync.
    func updateScanTargets(_ uuids: [String]) {
        scanTargetUUIDs = uuids
        restartScanIfPoweredOn()
    }

    // MARK: - Private helpers

    private func startAdvertisingIfPoweredOn() {
        guard peripheralManager.state == .poweredOn else { return }
        let serviceUUID = CBUUID(string: deviceUUID)
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])
    }

    private func restartScanIfPoweredOn() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.stopScan()
        guard !scanTargetUUIDs.isEmpty else { return }
        let targetCBUUIDs = scanTargetUUIDs.map { CBUUID(string: $0) }
        centralManager.scanForPeripherals(
            withServices: targetCBUUIDs,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}

// MARK: - CBCentralManagerDelegate

extension ProximityBluetoothService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            restartScanIfPoweredOn()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] else { return }
        for serviceUUID in serviceUUIDs {
            let uuidString = serviceUUID.uuidString
            if scanTargetUUIDs.contains(where: { $0.uppercased() == uuidString.uppercased() }) {
                DispatchQueue.main.async { [weak self] in
                    self?.onPeerDetected?(uuidString)
                }
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        // State restoration: resume scanning with previously active targets.
        // scanTargetUUIDs will be repopulated by VicinitApp on relaunch.
        // restartScanIfPoweredOn() is called once state = .poweredOn.
    }
}

// MARK: - CBPeripheralManagerDelegate

extension ProximityBluetoothService: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            startAdvertisingIfPoweredOn()
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        willRestoreState dict: [String: Any]
    ) {
        // Resume advertising after background restoration.
        startAdvertisingIfPoweredOn()
    }
}
