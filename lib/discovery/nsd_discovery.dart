import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:nsd/nsd.dart' as nsd;

import '../models/device.dart';
import '../models/device_status.dart';
import '../models/device_type.dart';
import 'discovery_interface.dart';

/// Implementation of [DeviceDiscovery] using the `nsd` plugin (mDNS / DNS-SD).
class NsdDeviceDiscovery implements DeviceDiscovery {
  final String serviceType;
  nsd.Discovery? _discoveryHandle;
  final _deviceController = StreamController<Device>.broadcast();
  final Map<String, Device> _discoveredDevices = {};
  bool _isScanning = false;

  NsdDeviceDiscovery({this.serviceType = kClipboardServiceType});

  @override
  bool get isScanning => _isScanning;

  @override
  Stream<Device> discover() => _deviceController.stream;

  @override
  Future<void> start() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      final discovery = await nsd.startDiscovery(serviceType);
      _discoveryHandle = discovery;

      discovery.addServiceListener((service, status) {
        if (status == nsd.ServiceStatus.found) {
          final device = _parseService(service);
          if (device != null) {
            _discoveredDevices[device.id] = device;
            _deviceController.add(device);
          }
        } else if (status == nsd.ServiceStatus.lost) {
          final id = service.name ?? '';
          if (_discoveredDevices.containsKey(id)) {
            final existing = _discoveredDevices[id]!;
            final offline = existing.copyWith(status: DeviceStatus.offline);
            _discoveredDevices.remove(id);
            _deviceController.add(offline);
          }
        }
      });
    } catch (e) {
      _isScanning = false;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isScanning) return;
    _isScanning = false;

    if (_discoveryHandle != null) {
      await nsd.stopDiscovery(_discoveryHandle!);
      _discoveryHandle = null;
    }
    _discoveredDevices.clear();
  }

  Device? _parseService(nsd.Service service) {
    final host = service.host ??
        (service.addresses?.isNotEmpty == true
            ? service.addresses!.first.address
            : null);
    final port = service.port ?? kDefaultClipboardPort;

    if (host == null) return null;

    // Decode TXT records if present
    final txt = <String, String>{};
    if (service.txt != null) {
      service.txt!.forEach((key, value) {
        if (value != null) {
          txt[key] = utf8.decode(value, allowMalformed: true);
        }
      });
    }

    final id = txt['id'] ?? service.name ?? host;
    final name = txt['name'] ?? service.name ?? 'Android TV';
    final typeStr = txt['type'] ?? 'android_tv';

    return Device(
      id: id,
      name: name,
      type: DeviceType.fromJson(typeStr),
      address: host,
      port: port,
      status: DeviceStatus.online,
      lastSeen: DateTime.now().toUtc(),
      metadata: txt,
    );
  }

  void dispose() {
    stop();
    _deviceController.close();
  }
}

/// Implementation of [DeviceAdvertiser] using the `nsd` plugin (mDNS / DNS-SD).
class NsdDeviceAdvertiser implements DeviceAdvertiser {
  final String serviceType;
  nsd.Registration? _registration;
  bool _isAdvertising = false;

  NsdDeviceAdvertiser({this.serviceType = kClipboardServiceType});

  @override
  bool get isAdvertising => _isAdvertising;

  @override
  Future<void> startAdvertising({
    required String serviceName,
    required int port,
    Map<String, String>? txtRecords,
  }) async {
    if (_isAdvertising) return;

    final encodedTxt = <String, Uint8List?>{};
    txtRecords?.forEach((key, value) {
      encodedTxt[key] = Uint8List.fromList(utf8.encode(value));
    });

    final service = nsd.Service(
      name: serviceName,
      type: serviceType,
      port: port,
      txt: encodedTxt.isNotEmpty ? encodedTxt : null,
    );

    _registration = await nsd.register(service);
    _isAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    if (!_isAdvertising || _registration == null) return;

    await nsd.unregister(_registration!);
    _registration = null;
    _isAdvertising = false;
  }
}
