// Araç Kutusu motoru: iOS yerel eklentisi.
//
// arac_motoru/bt (durum, ayarlar) ve arac_motoru/bt_scan (tarama akışı):
// CoreBluetooth ile yakındaki BLE cihazlarının adı ve sinyal gücü okunur.
// Bağlantı kurulmaz, konum alınmaz, ağ kullanılmaz.
import CoreBluetooth
import Flutter
import UIKit

public class AracMotoruPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CBCentralManagerDelegate {
  private var central: CBCentralManager?
  private var sink: FlutterEventSink?
  private var pendingState: [FlutterResult] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AracMotoruPlugin()
    let channel = FlutterMethodChannel(name: "arac_motoru/bt", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(name: "arac_motoru/bt_scan", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  private func manager() -> CBCentralManager {
    if let c = central { return c }
    let c = CBCentralManager(delegate: self, queue: nil)
    central = c
    return c
  }

  private func stateName(_ s: CBManagerState) -> String {
    switch s {
    case .poweredOn: return "on"
    case .poweredOff: return "off"
    case .unauthorized: return "unauthorized"
    case .unsupported: return "unsupported"
    default: return "unknown"
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "state":
      let m = manager()
      if m.state == .unknown || m.state == .resetting {
        pendingState.append(result)
      } else {
        result(stateName(m.state))
      }
    case "settings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
        result(true)
      } else {
        result(false)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    let m = manager()
    if m.state == .poweredOn { startScan() }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    central?.stopScan()
    sink = nil
    return nil
  }

  private func startScan() {
    central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
  }

  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let name = stateName(central.state)
    if central.state != .unknown && central.state != .resetting {
      let waiting = pendingState
      pendingState = []
      for r in waiting { r(name) }
    }
    if central.state == .poweredOn {
      if sink != nil { startScan() }
    } else if central.state != .unknown && central.state != .resetting, let s = sink {
      s(FlutterError(code: name, message: name, details: nil))
    }
  }

  public func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    guard let s = sink else { return }
    let rssi = RSSI.intValue
    if rssi == 127 { return }  // 127: ölçüm yok
    let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
    s([
      "id": peripheral.identifier.uuidString,
      "name": name,
      "rssi": rssi,
      "type": "le",
      "bonded": false,
    ])
  }
}
