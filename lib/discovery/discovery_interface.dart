import '../models/device.dart';

/// Service type used for local DNS-SD / mDNS discovery.
const String kClipboardServiceType = '_clipboard._tcp';

/// Default TCP port for Clipboard Sharer WebSocket server.
const int kDefaultClipboardPort = 43824;

/// Abstract interface for discovering Clipboard Sharer TV devices on the LAN.
abstract class DeviceDiscovery {
  /// Stream emitting discovered or updated devices on the local network.
  Stream<Device> discover();

  /// Starts scanning/listening for advertised devices.
  Future<void> start();

  /// Stops discovery.
  Future<void> stop();

  /// Whether discovery is currently active.
  bool get isScanning;
}

/// Abstract interface for advertising a TV / receiver service on the LAN.
abstract class DeviceAdvertiser {
  /// Starts advertising the local device service via mDNS.
  Future<void> startAdvertising({
    required String serviceName,
    required int port,
    Map<String, String>? txtRecords,
  });

  /// Stops advertising.
  Future<void> stopAdvertising();

  /// Whether advertising is currently active.
  bool get isAdvertising;
}
