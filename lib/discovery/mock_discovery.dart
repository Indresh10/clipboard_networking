import 'dart:async';
import '../models/device.dart';
import '../models/device_status.dart';
import '../models/device_type.dart';
import 'discovery_interface.dart';

/// In-memory discovery hub that connects mock advertisers and mock discoverers.
/// Useful for unit testing, test environments, and local simulations.
class MockDiscoveryHub {
  static final MockDiscoveryHub instance = MockDiscoveryHub._();
  MockDiscoveryHub._();

  final List<MockDeviceDiscovery> _listeners = [];
  final Map<String, Device> _registeredDevices = {};

  void registerAdvertiser(String serviceName, int port, Map<String, String>? txtRecords) {
    final id = txtRecords?['id'] ?? serviceName;
    final name = txtRecords?['name'] ?? serviceName;
    final type = DeviceType.fromJson(txtRecords?['type'] ?? 'android_tv');
    final host = txtRecords?['host'] ?? '127.0.0.1';

    final device = Device(
      id: id,
      name: name,
      type: type,
      address: host,
      port: port,
      status: DeviceStatus.online,
      lastSeen: DateTime.now().toUtc(),
      metadata: txtRecords ?? {},
    );

    _registeredDevices[id] = device;
    for (final listener in List.of(_listeners)) {
      listener._notifyDevice(device);
    }
  }

  void unregisterAdvertiser(String serviceName, Map<String, String>? txtRecords) {
    final id = txtRecords?['id'] ?? serviceName;
    final existing = _registeredDevices.remove(id);
    if (existing != null) {
      final offline = existing.copyWith(status: DeviceStatus.offline);
      for (final listener in List.of(_listeners)) {
        listener._notifyDevice(offline);
      }
    }
  }

  void attachDiscovery(MockDeviceDiscovery discovery) {
    _listeners.add(discovery);
    for (final dev in _registeredDevices.values) {
      discovery._notifyDevice(dev);
    }
  }

  void detachDiscovery(MockDeviceDiscovery discovery) {
    _listeners.remove(discovery);
  }

  void reset() {
    _registeredDevices.clear();
    _listeners.clear();
  }
}

/// In-memory mock implementation of [DeviceDiscovery].
class MockDeviceDiscovery implements DeviceDiscovery {
  final _controller = StreamController<Device>.broadcast();
  bool _isScanning = false;

  @override
  bool get isScanning => _isScanning;

  @override
  Stream<Device> discover() => _controller.stream;

  @override
  Future<void> start() async {
    _isScanning = true;
    MockDiscoveryHub.instance.attachDiscovery(this);
  }

  @override
  Future<void> stop() async {
    _isScanning = false;
    MockDiscoveryHub.instance.detachDiscovery(this);
  }

  void _notifyDevice(Device device) {
    if (_isScanning && !_controller.isClosed) {
      _controller.add(device);
    }
  }

  /// Manually inject a discovered device for testing.
  void injectDevice(Device device) {
    _notifyDevice(device);
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// In-memory mock implementation of [DeviceAdvertiser].
class MockDeviceAdvertiser implements DeviceAdvertiser {
  bool _isAdvertising = false;
  String? _serviceName;
  Map<String, String>? _txtRecords;

  @override
  bool get isAdvertising => _isAdvertising;

  @override
  Future<void> startAdvertising({
    required String serviceName,
    required int port,
    Map<String, String>? txtRecords,
  }) async {
    _serviceName = serviceName;
    _txtRecords = txtRecords;
    _isAdvertising = true;
    MockDiscoveryHub.instance.registerAdvertiser(serviceName, port, txtRecords);
  }

  @override
  Future<void> stopAdvertising() async {
    if (_isAdvertising && _serviceName != null) {
      MockDiscoveryHub.instance.unregisterAdvertiser(_serviceName!, _txtRecords);
      _isAdvertising = false;
      _serviceName = null;
    }
  }
}
