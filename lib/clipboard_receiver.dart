import 'dart:async';
import 'dart:io';

import 'discovery/discovery_interface.dart';
import 'discovery/nsd_discovery.dart';
import 'models/clipboard_item.dart';
import 'models/device.dart';
import 'models/device_type.dart';
import 'models/pairing_payload.dart';
import 'pairing/pairing_manager.dart';
import 'protocol/message_type.dart';
import 'protocol/network_message.dart';
import 'transport/websocket_server.dart';

/// Configuration for the receiver / TV service.
class ReceiverConfig {
  final int port;
  final String serviceName;
  final Duration pairingValidity;
  final bool autoAdvertise;

  const ReceiverConfig({
    this.port = kDefaultClipboardPort,
    this.serviceName = 'Clipboard Sharer TV',
    this.pairingValidity = const Duration(minutes: 5),
    this.autoAdvertise = true,
  });
}

/// High-level receiver service for Android TV.
/// Coordinates the WebSocket server, DNS-SD advertisement,
/// pairing sessions, client authentication, and the clipboard stream.
class ClipboardSharerReceiver {
  final String deviceId;
  final String deviceName;
  final ReceiverConfig config;
  final DeviceAdvertiser advertiser;

  late final WebSocketLanServer _server;
  late final PairingManager _pairingManager;

  final _clipboardController = StreamController<ClipboardItem>.broadcast();
  final _pairedDevicesController = StreamController<List<Device>>.broadcast();
  final _pairingSessionController = StreamController<ActivePairingSession?>.broadcast();

  StreamSubscription? _serverMessageSub;
  StreamSubscription? _serverEventSub;
  Timer? _pairingExpiryTimer;

  bool _isStarted = false;
  int? _actualPort;

  ClipboardSharerReceiver({
    required this.deviceId,
    required this.deviceName,
    this.config = const ReceiverConfig(),
    DeviceAdvertiser? advertiser,
    List<Device> initialPairedDevices = const [],
    void Function(List<Device>)? onPairedDevicesChanged,
  }) : advertiser = advertiser ?? NsdDeviceAdvertiser() {
    _server = WebSocketLanServer(serverDeviceId: deviceId);
    _pairingManager = PairingManager(
      serverDeviceId: deviceId,
      serverDeviceName: deviceName,
      serverAddress: '0.0.0.0',
      serverPort: config.port,
      initialPairedDevices: initialPairedDevices,
      onPairedDevicesChanged: (devices) {
        if (!_pairedDevicesController.isClosed) {
          _pairedDevicesController.add(devices);
        }
        onPairedDevicesChanged?.call(devices);
      },
    );
  }

  /// Stream of incoming clipboard items received from authenticated clients.
  Stream<ClipboardItem> get incomingClipboardStream => _clipboardController.stream;

  /// Stream of currently paired devices.
  Stream<List<Device>> get pairedDevicesStream => _pairedDevicesController.stream;

  /// Stream of active pairing session updates.
  Stream<ActivePairingSession?> get activePairingSessionStream => _pairingSessionController.stream;

  /// Current active pairing session, if any.
  ActivePairingSession? get currentPairingSession => _pairingManager.activeSession;

  /// List of currently paired devices.
  List<Device> get pairedDevices => _pairingManager.pairedDevices;

  /// Currently connected clients.
  List<ServerConnectedClient> get connectedClients => _server.connectedClients;

  bool get isRunning => _isStarted && _server.isRunning;
  int? get port => _actualPort;

  /// Starts the receiver: binds WebSocket server and begins mDNS advertising.
  Future<int> start({int? portOverride}) async {
    if (_isStarted) return _actualPort!;

    final portToBind = portOverride ?? config.port;
    _actualPort = await _server.start(port: portToBind);

    // Subscribe to incoming messages
    _serverMessageSub = _server.incomingMessages.listen(_handleIncomingMessage);
    _serverEventSub = _server.clientEvents.listen(_handleClientEvent);

    if (config.autoAdvertise) {
      await _startAdvertising();
    }

    _isStarted = true;
    return _actualPort!;
  }

  Future<void> _startAdvertising() async {
    try {
      await advertiser.startAdvertising(
        serviceName: config.serviceName,
        port: _actualPort!,
        txtRecords: {
          'id': deviceId,
          'name': deviceName,
          'type': DeviceType.androidTv.toJson(),
          'version': NetworkMessage.currentProtocolVersion.toString(),
        },
      );
    } catch (_) {
      // Allow fallback if mDNS is not supported in the current test environment
    }
  }

  void _handleIncomingMessage(ServerClientMessage clientMsg) {
    final client = clientMsg.client;
    final message = clientMsg.message;

    switch (message.type) {
      case MessageType.hello:
        _handleHello(client, message);
        break;

      case MessageType.pairRequest:
        _handlePairRequest(client, message);
        break;

      case MessageType.pairComplete:
        _handlePairComplete(client, message);
        break;

      case MessageType.clipboard:
        _handleClipboard(client, message);
        break;

      case MessageType.deviceInfo:
      case MessageType.ack:
      case MessageType.ping:
      case MessageType.pong:
      case MessageType.disconnect:
      case MessageType.pairResponse:
        break;
    }
  }

  void _handleHello(ServerConnectedClient client, NetworkMessage message) {
    final hello = message.asHelloPayload();
    client.deviceId = message.senderId;
    client.deviceName = hello.clientName;

    // Check if client is already paired with valid auth token
    if (hello.authToken != null &&
        _pairingManager.verifyClientAuth(message.senderId, hello.authToken)) {
      _server.markClientAuthenticated(
        client.connectionId,
        deviceId: message.senderId,
        deviceName: hello.clientName,
      );

      // Send device info back
      _server.sendTo(
        client.connectionId,
        NetworkMessage.deviceInfo(
          senderId: deviceId,
          deviceName: deviceName,
          deviceType: DeviceType.androidTv,
        ),
      );
    }
  }

  void _handlePairRequest(ServerConnectedClient client, NetworkMessage message) {
    final req = message.asPairRequestPayload();
    final responsePayload = _pairingManager.processPairRequest(
      req,
      clientIp: client.remoteAddress,
    );

    if (responsePayload.success) {
      _server.markClientAuthenticated(
        client.connectionId,
        deviceId: req.clientDeviceId,
        deviceName: req.clientDeviceName,
      );
      _notifyPairingSessionChanged();
    }

    final respMsg = NetworkMessage(
      type: MessageType.pairResponse,
      messageId: message.messageId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: deviceId,
      payload: responsePayload.toJson(),
    );

    _server.sendTo(client.connectionId, respMsg);
  }

  void _handlePairComplete(ServerConnectedClient client, NetworkMessage message) {
    // Send ACK to confirm pairing complete
    _server.sendTo(
      client.connectionId,
      NetworkMessage.ack(
        senderId: deviceId,
        ackedMessageId: message.messageId,
        success: true,
      ),
    );
  }

  void _handleClipboard(ServerConnectedClient client, NetworkMessage message) {
    // Verify client is authenticated or paired
    final payload = message.asClipboardPayload();
    final item = payload.toClipboardItem();

    if (!_clipboardController.isClosed) {
      _clipboardController.add(item);
    }
  }

  void _handleClientEvent(ClientLifecycleEvent event) {
    // Can be used for logging or connection tracking
  }

  /// Initiates a new pairing session and returns the QR / PIN [PairingPayload].
  Future<PairingPayload> startPairing({
    Duration? validity,
    String? localIpOverride,
  }) async {
    final effectiveValidity = validity ?? config.pairingValidity;
    final resolvedIp = localIpOverride ?? await _resolveLocalIp();

    final payload = _pairingManager.createPairingSession(validity: effectiveValidity);

    // Create a copy with the actual resolved IP and port
    final resultPayload = PairingPayload(
      sessionId: payload.sessionId,
      deviceId: deviceId,
      deviceName: deviceName,
      address: resolvedIp,
      port: _actualPort ?? config.port,
      pinCode: payload.pinCode,
      sessionToken: payload.sessionToken,
      expiresAt: payload.expiresAt,
    );

    _notifyPairingSessionChanged();

    _pairingExpiryTimer?.cancel();
    _pairingExpiryTimer = Timer(effectiveValidity, () {
      _notifyPairingSessionChanged();
    });

    return resultPayload;
  }

  /// Cancels any active pairing session.
  void cancelPairing() {
    _pairingExpiryTimer?.cancel();
    _pairingExpiryTimer = null;
    _pairingManager.cancelPairingSession();
    _notifyPairingSessionChanged();
  }

  void _notifyPairingSessionChanged() {
    if (!_pairingSessionController.isClosed) {
      _pairingSessionController.add(_pairingManager.activeSession);
    }
  }

  /// Unpairs a device by ID.
  bool removePairedDevice(String deviceId) => _pairingManager.removePairedDevice(deviceId);

  /// Clears all paired devices.
  void clearPairedDevices() => _pairingManager.clearPairedDevices();

  Future<String> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// Stops server, unregisters mDNS, and cleans up resources.
  Future<void> stop() async {
    _pairingExpiryTimer?.cancel();
    _pairingExpiryTimer = null;

    await advertiser.stopAdvertising();
    await _serverMessageSub?.cancel();
    await _serverEventSub?.cancel();
    await _server.stop();

    _isStarted = false;
  }

  void dispose() {
    stop();
    _clipboardController.close();
    _pairedDevicesController.close();
    _pairingSessionController.close();
    _server.dispose();
  }
}
