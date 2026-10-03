import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

import '../discovery/discovery_interface.dart';
import '../protocol/message_type.dart';
import '../protocol/network_message.dart';

/// Represents a single client connected to the [WebSocketLanServer].
class ServerConnectedClient {
  final String connectionId;
  final WebSocket socket;
  final String remoteAddress;
  final int remotePort;
  final DateTime connectedAt;

  String? deviceId;
  String? deviceName;
  bool isAuthenticated;
  DateTime lastSeen;

  ServerConnectedClient({
    required this.connectionId,
    required this.socket,
    required this.remoteAddress,
    required this.remotePort,
    required this.connectedAt,
    this.deviceId,
    this.deviceName,
    this.isAuthenticated = false,
  }) : lastSeen = connectedAt;
}

/// Message received from a specific connected client.
class ServerClientMessage {
  final ServerConnectedClient client;
  final NetworkMessage message;

  const ServerClientMessage({
    required this.client,
    required this.message,
  });
}

/// Lifecycle event for clients connecting to or disconnecting from the server.
enum ClientLifecycleType { connected, authenticated, disconnected }

class ClientLifecycleEvent {
  final ClientLifecycleType type;
  final ServerConnectedClient client;
  final String? reason;

  const ClientLifecycleEvent({
    required this.type,
    required this.client,
    this.reason,
  });
}

/// WebSocket server running on the TV / receiver side.
class WebSocketLanServer {
  static const _uuid = Uuid();

  final String serverDeviceId;
  final bool autoAckClipboard;

  HttpServer? _httpServer;
  final Map<String, ServerConnectedClient> _clients = {};

  final _messagesController = StreamController<ServerClientMessage>.broadcast();
  final _clientEventsController = StreamController<ClientLifecycleEvent>.broadcast();

  WebSocketLanServer({
    required this.serverDeviceId,
    this.autoAckClipboard = true,
  });

  bool get isRunning => _httpServer != null;
  int? get port => _httpServer?.port;
  String? get address => _httpServer?.address.address;

  Stream<ServerClientMessage> get incomingMessages => _messagesController.stream;
  Stream<ClientLifecycleEvent> get clientEvents => _clientEventsController.stream;

  List<ServerConnectedClient> get connectedClients => _clients.values.toList();

  /// Starts the HTTP / WebSocket server on the specified port.
  /// If port is 0, an ephemeral available port will be chosen by the OS.
  Future<int> start({
    int port = kDefaultClipboardPort,
    InternetAddress? address,
  }) async {
    if (isRunning) return _httpServer!.port;

    final bindAddress = address ?? InternetAddress.anyIPv4;
    _httpServer = await HttpServer.bind(bindAddress, port);
    _httpServer!.listen(_handleHttpRequest);

    return _httpServer!.port;
  }

  void _handleHttpRequest(HttpRequest request) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      WebSocketTransformer.upgrade(request).then((socket) {
        _handleNewWebSocket(socket, request);
      }).catchError((e) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.close();
      });
    } else {
      // Respond to basic healthcheck or info
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'service': 'Clipboard Sharer',
          'serverDeviceId': serverDeviceId,
          'status': 'ready',
        }))
        ..close();
    }
  }

  void _handleNewWebSocket(WebSocket socket, HttpRequest request) {
    final connId = _uuid.v4();
    final client = ServerConnectedClient(
      connectionId: connId,
      socket: socket,
      remoteAddress: request.connectionInfo?.remoteAddress.address ?? 'unknown',
      remotePort: request.connectionInfo?.remotePort ?? 0,
      connectedAt: DateTime.now().toUtc(),
    );

    _clients[connId] = client;
    _emitClientEvent(ClientLifecycleType.connected, client);

    socket.listen(
      (data) => _onClientData(client, data),
      onError: (err) => _onClientDisconnect(client, reason: 'Error: $err'),
      onDone: () => _onClientDisconnect(client, reason: 'Connection closed'),
      cancelOnError: true,
    );
  }

  void _onClientData(ServerConnectedClient client, dynamic rawData) {
    try {
      final rawString = rawData is List<int> ? utf8.decode(rawData) : rawData.toString();
      final message = NetworkMessage.decode(rawString);

      client.lastSeen = DateTime.now().toUtc();
      if (client.deviceId == null && message.senderId.isNotEmpty) {
        client.deviceId = message.senderId;
      }

      // Handle internal protocol messages
      if (message.type == MessageType.ping) {
        final ping = message.asPingPayload();
        sendTo(client.connectionId, NetworkMessage.pong(senderId: serverDeviceId, sequence: ping.sequence));
        return;
      }

      if (message.type == MessageType.pong) {
        return;
      }

      if (message.type == MessageType.disconnect) {
        disconnectClient(client.connectionId, reason: 'Client requested disconnect');
        return;
      }

      // Automatic ACK for clipboard messages if enabled
      if (message.type == MessageType.clipboard && autoAckClipboard) {
        sendTo(
          client.connectionId,
          NetworkMessage.ack(
            senderId: serverDeviceId,
            ackedMessageId: message.messageId,
            success: true,
          ),
        );
      }

      // Forward to incoming messages stream
      if (!_messagesController.isClosed) {
        _messagesController.add(ServerClientMessage(client: client, message: message));
      }
    } catch (_) {
      // Discard invalid / malformed messages
    }
  }

  void _onClientDisconnect(ServerConnectedClient client, {String? reason}) {
    if (_clients.remove(client.connectionId) != null) {
      _emitClientEvent(ClientLifecycleType.disconnected, client, reason: reason);
      try {
        client.socket.close();
      } catch (_) {}
    }
  }

  void _emitClientEvent(ClientLifecycleType type, ServerConnectedClient client, {String? reason}) {
    if (!_clientEventsController.isClosed) {
      _clientEventsController.add(ClientLifecycleEvent(type: type, client: client, reason: reason));
    }
  }

  /// Sends a message to a specific connected client.
  void sendTo(String connectionId, NetworkMessage message) {
    final client = _clients[connectionId];
    if (client != null) {
      try {
        client.socket.add(message.encode());
      } catch (_) {
        _onClientDisconnect(client, reason: 'Failed to write to socket');
      }
    }
  }

  /// Sends a message to a specific client identified by [deviceId].
  void sendToDevice(String deviceId, NetworkMessage message) {
    for (final client in _clients.values) {
      if (client.deviceId == deviceId) {
        sendTo(client.connectionId, message);
      }
    }
  }

  /// Broadcasts a message to all connected clients (optionally only authenticated ones).
  void broadcast(NetworkMessage message, {bool onlyAuthenticated = false}) {
    final encoded = message.encode();
    for (final client in _clients.values) {
      if (!onlyAuthenticated || client.isAuthenticated) {
        try {
          client.socket.add(encoded);
        } catch (_) {}
      }
    }
  }

  /// Disconnects a specific client gracefully.
  void disconnectClient(String connectionId, {String reason = 'Disconnected by server'}) {
    final client = _clients[connectionId];
    if (client != null) {
      try {
        sendTo(connectionId, NetworkMessage.disconnect(senderId: serverDeviceId, reason: reason));
      } catch (_) {}
      _onClientDisconnect(client, reason: reason);
    }
  }

  /// Marks a connected client as authenticated.
  void markClientAuthenticated(String connectionId, {required String deviceId, String? deviceName}) {
    final client = _clients[connectionId];
    if (client != null) {
      client.deviceId = deviceId;
      if (deviceName != null) client.deviceName = deviceName;
      client.isAuthenticated = true;
      _emitClientEvent(ClientLifecycleType.authenticated, client);
    }
  }

  /// Stops the server and closes all active client connections.
  Future<void> stop() async {
    final clientList = _clients.values.toList();
    for (final client in clientList) {
      disconnectClient(client.connectionId, reason: 'Server shutting down');
    }
    _clients.clear();

    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  void dispose() {
    stop();
    _messagesController.close();
    _clientEventsController.close();
  }
}
