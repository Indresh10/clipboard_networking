import 'dart:async';

import 'discovery/discovery_interface.dart';
import 'discovery/nsd_discovery.dart';
import 'models/clipboard_item.dart';
import 'models/connection_state.dart';
import 'models/device.dart';
import 'models/device_status.dart';
import 'models/device_type.dart';
import 'models/pairing_payload.dart';
import 'pairing/pairing_client_service.dart';
import 'pairing/pairing_manager.dart';
import 'protocol/network_message.dart';
import 'transport/lan_connection.dart';
import 'transport/websocket_client.dart';

/// High-level client used by Mobile (Android, iOS) and Windows Desktop apps.
/// Coordinates mDNS discovery, connection lifecycle, pairing (QR & PIN),
/// and clipboard transmission with delivery acknowledgments.
class ClipboardSharerClient {
  final String deviceId;
  final String deviceName;
  final DeviceType deviceType;

  final DeviceDiscovery discovery;
  final LanConnection connection;
  late final PairingClientService _pairingService;

  final Map<String, Device> _discoveredDevices = {};
  final _discoveredDevicesController =
      StreamController<List<Device>>.broadcast();

  StreamSubscription? _discoverySub;
  StreamSubscription? _connectionStateSub;

  ClipboardSharerClient({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    DeviceDiscovery? discovery,
    LanConnection? connection,
  })  : discovery = discovery ?? NsdDeviceDiscovery(),
        connection = connection ?? WebSocketLanClient(localDeviceId: deviceId) {
    _pairingService = PairingClientService(
      localDeviceId: deviceId,
      localDeviceName: deviceName,
      localDeviceType: deviceType,
    );

    _discoverySub = this.discovery.discover().listen(_onDeviceDiscovered);
  }

  /// Stream of currently discovered TV devices on the LAN.
  Stream<List<Device>> get discoveredDevicesStream =>
      _discoveredDevicesController.stream;

  /// Current list of discovered TV devices.
  List<Device> get discoveredDevices => _discoveredDevices.values.toList();

  /// Stream of connection state transitions.
  Stream<ConnectionState> get connectionStateStream => connection.state;

  /// Current connection state.
  ConnectionState get connectionState => connection.currentState;

  /// Currently connected device.
  Device? get connectedDevice => connection.targetDevice;

  void _onDeviceDiscovered(Device device) {
    if (device.status == DeviceStatus.offline) {
      _discoveredDevices.remove(device.id);
    } else {
      _discoveredDevices[device.id] = device;
    }
    if (!_discoveredDevicesController.isClosed) {
      _discoveredDevicesController.add(discoveredDevices);
    }
  }

  /// Starts scanning the LAN for available TV receivers.
  Future<void> startDiscovery() async {
    _discoveredDevices.clear();
    await discovery.start();
  }

  /// Stops LAN discovery scanning.
  Future<void> stopDiscovery() async {
    await discovery.stop();
  }

  /// Connects to a target TV device and performs HELLO handshake.
  Future<void> connect(Device targetDevice, {String? authToken}) async {
    await connection.connect(targetDevice);

    // Send HELLO handshake
    final helloMsg = NetworkMessage.hello(
      senderId: deviceId,
      clientName: deviceName,
      deviceType: deviceType,
      authToken: authToken,
    );
    await connection.send(helloMsg);
  }

  /// Pairs with a TV using a scanned QR payload (Mobile flow).
  Future<PairingResult> pairWithQr(
    PairingPayload qrPayload, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return _pairingService.pairWithQrPayload(
      payload: qrPayload,
      connection: connection,
      timeout: timeout,
    );
  }

  /// Pairs with a TV using a 6-digit numeric PIN (Desktop flow).
  Future<PairingResult> pairWithPin(
    Device tvDevice,
    String pinCode, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return _pairingService.pairWithPin(
      tvDevice: tvDevice,
      pinCode: pinCode,
      connection: connection,
      timeout: timeout,
    );
  }

  /// Sends a clipboard item to the connected TV and awaits delivery ACK.
  Future<bool> sendClipboard(
    ClipboardItem item, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (connection.currentState != ConnectionState.connected) {
      throw StateError(
          'Cannot send clipboard: client is not connected to a TV');
    }

    final message = NetworkMessage.clipboard(
      senderId: deviceId,
      item: item,
    );

    if (connection is WebSocketLanClient) {
      final ack = await (connection as WebSocketLanClient)
          .sendWithAck(message, timeout: timeout);
      return ack.success;
    } else {
      await connection.send(message);
      return true;
    }
  }

  /// Sends raw text as a new clipboard item.
  Future<bool> sendText(
    String text, {
    bool sensitive = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final item = ClipboardItem(
      id: '${NetworkMessage.currentProtocolVersion}-${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      createdAt: DateTime.now().toUtc(),
      sourceDeviceId: deviceId,
      sensitive: sensitive,
    );
    return sendClipboard(item, timeout: timeout);
  }

  /// Gracefully disconnects from the current TV.
  Future<void> disconnect({String reason = 'Normal closure'}) async {
    await connection.disconnect(reason: reason);
  }

  /// Disposes resources, subscriptions, and streams.
  void dispose() {
    _discoverySub?.cancel();
    _connectionStateSub?.cancel();
    discovery.stop();
    connection.dispose();
    _discoveredDevicesController.close();
  }
}
